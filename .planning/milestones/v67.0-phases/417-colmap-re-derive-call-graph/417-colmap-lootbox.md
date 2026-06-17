# Column Map — Slice: LootboxModule

Subject: frozen `contracts/` tree `0dd445a6`
File: `contracts/modules/DegenerusGameLootboxModule.sol` (2329 lines)
Context: ALL functions execute via `delegatecall` from `DegenerusGame` in the GAME's storage. Storage writes named here land in GAME slots. Inherited helpers (from `DegenerusGameStorage`) are referenced where the column reaches them; their internal reverts/loops/writes are surfaced because they execute inside this slice's frames.

External (synchronous CALL, not delegatecall) targets reachable in this slice:
- `coinflip` = `ICoinflip(ContractAddresses.COINFLIP)` — `.creditFlip`
- `dgnrs` = `IsDGNRS(ContractAddresses.SDGNRS)`/Pool token — `.poolBalance`, `.transferFromPool`
- `wwxrp` = `IWrappedWrappedXRP(ContractAddresses.WWXRP)` — `.mintPrize`
- `steth` = `IStETH(ContractAddresses.STETH_TOKEN)` — `.transferFrom`
- `IDegenerusQuests(ContractAddresses.QUESTS)` — `.awardQuestStreakShield`

Module delegatecall targets reachable in this slice:
- `ContractAddresses.GAME_BOON_MODULE` — `consumeActivityBoon`, `checkAndClearExpiredBoon`
- `ContractAddresses.GAME_DEGENERETTE_MODULE` — `resolveWwxrpSpinFromBox`, `resolveFlipSpinsFromBox`, `resolveEthSpinFromBox`

---

## 1. CALL GRAPH (column-reachable functions)

Column entrypoints into this slice (all `external`, reached by a Game stub delegatecall):
- `openHumanBoxes(uint256 budget)` — the openBoxes() human-leg multi-index sweep (AUTO-03).
- `openBox(address,uint48)` — manual both-leg open.
- `resolveLootboxDirect(address,uint256,uint256,uint16,bool) payable` — decimator/degenerette win recirc.
- `resolveRedemptionLootbox(address,uint256,uint256,uint16) payable` — sDGNRS gambling-burn claim.
- `creditRedemptionDirect(address,uint256) payable` — sDGNRS redemption direct-half credit.
- `resolveAfkingBox(address,uint256,uint24,uint256,uint16)` — afking-subscription box open (GameAfkingModule open-leg).
- `issueDeityBoon(address,address,uint8)` — deity boon issuance.

### openHumanBoxes (external) — L656
- internal: `_lrRead`†, `_livenessTriggered`†, `_openLootBoxLegWith`, `_resolvePresaleBox`
- reads slot-0 fields: `rngLockedFlag`, `boxCursorIndex`, `boxCursor`, `presaleDrained`, `presaleOver`, `presaleCloseIndex`
- delegatecalls: (transitively via `_openLootBoxLegWith` → `_resolveLootboxCommon`) GAME_BOON_MODULE, GAME_DEGENERETTE_MODULE — **NESTED** (this fn is itself reached by a Game→module delegatecall)
- external: (transitive) coinflip.creditFlip, dgnrs.*, wwxrp.mintPrize

### openBox (external) — L605
- internal: `_openBoxBoth` → `_openLootBoxLeg` → `_openLootBoxLegWith`; `_resolvePresaleBox`
- revert: `revert E()` when neither leg queued
- delegatecalls/external: same transitive set as above (**NESTED**)

### _openLootBoxLeg (internal) — L520
- reads `lootboxEth[index][player]`, `lootboxRngWordByIndex[index]`
- internal: `_openLootBoxLegWith`

### _openLootBoxLegWith (internal) — L535
- internal: `_unpackLootbox`†, `_rollTargetLevel`, `_lootboxEvMultiplierFromScore`†, `_resolveLootboxCommon`
- reads `level`; **writes `lootboxEth[index][player] = 0`** (L579)
- revert: `RngNotReady` (L545)

### _openBoxBoth (internal) — L621
- internal: `_openLootBoxLeg`, `_resolvePresaleBox`
- reads `presaleBoxEth[index][player]`, `lootboxRngWordByIndex[index]`
- **writes `presaleBoxEth[index][player] = 0`** (L632)
- revert: `RngNotReady` (L631)

### resolveLootboxDirect (external payable) — L874
- internal: `EntropyLib.hash2`, `_rollTargetLevel`, `_lootboxEvMultiplierFromScore`†, `_applyEvMultiplierWithCap`, `_resolveLootboxCommon`
- reads `level`; (via `_applyEvMultiplierWithCap`) **writes `lootboxEvCapPacked[player]`**
- delegatecalls/external: transitive via `_resolveLootboxCommon` (**NESTED** — reached via Game→module delegatecall; itself `payable`, see risk notes)

### resolveRedemptionLootbox (external payable) — L926
- revert: `E()` if `msg.sender != SDGNRS` (L927); `E()` if `msg.value > amount` (L931); `E()` if `!steth.transferFrom(...)` (L935)
- external: **steth.transferFrom** (L935)
- internal: `_getPendingPools`†/`_setPendingPools`† or `_getPrizePools`†/`_setPrizePools`†; loop → `_resolveRedemptionChunk`; `EntropyLib.hash1`
- **writes `prizePoolPendingPacked` (frozen branch) or `prizePoolsPacked`** (L943/L946)
- LOOP L951 (5-ETH chunking)

### _resolveRedemptionChunk (private) — L965
- internal: `_rollTargetLevel`, `_lootboxEvMultiplierFromScore`†, `_applyEvMultiplierWithCap`, `_resolveLootboxCommon`
- reads `level`; **writes `lootboxEvCapPacked[player]`** (via cap)

### creditRedemptionDirect (external payable) — L1004
- revert: `E()` if `msg.sender != SDGNRS` (L1005); `E()` if `msg.value > amount` (L1006); `E()` if `!steth.transferFrom` (L1011)
- external: **steth.transferFrom** (L1011)
- internal: `_creditClaimable`† → **writes `balancesPacked[player]`** (L936); **writes `claimablePool += amount`** (L1014)

### resolveAfkingBox (external) — L1072
- internal: `_rollTargetLevel`, `_lootboxEvMultiplierFromScore`†, `_applyEvMultiplierWithCap`, `_resolveLootboxCommon`
- reads `level`; **writes `lootboxEvCapPacked[player]`** (via cap)
- delegatecalls/external: transitive via `_resolveLootboxCommon` (**NESTED**)

### issueDeityBoon (external) — L1132
- revert: 7 `E()` sites (L1133/L1134/L1135/L1136/L1140/L1147/L1150)
- internal: `_simulatedDayIndex`†, `_isDecimatorWindow`, `_deityBoonForSlot`, `_applyBoon`
- reads `mintPacked_[deity]`, `rngWordByDay[day]`, `deityBoonPacked[deity]`, `deityBoonRecipientDay[recipient]`, `deityPassOwners.length`
- **writes `deityBoonPacked[deity]`** (L1151), **`deityBoonRecipientDay[recipient]`** (L1154)

### _resolvePresaleBox (private) — L737
- internal: `PriceLookupLib.priceForLevel`, `_presaleBoxDgnrsReward`
- reads `level`
- external: **coinflip.creditFlip** (L779), **dgnrs.poolBalance** (L794), **dgnrs.transferFromPool** (L798), **wwxrp.mintPrize** (L787)

### _presaleBoxDgnrsReward (private) — L817
- reads/writes **`presaleBoxDgnrsPoolStart`** (L822/L826)
- external: **dgnrs.poolBalance** (L824), **dgnrs.transferFromPool** (L834)

### _resolveLootboxCommon (private) — L1247
- internal: `_lootboxBoonBudget`, `_rollLootboxBoons`, `_rollTargetLevel`, `EntropyLib.hash2`, `_settleLootboxRoll`
- delegatecall: **GAME_BOON_MODULE.consumeActivityBoon** (L1281) — **NESTED**
- revert: `E()` if `!okAct` (L1284)
- reads `boonPacked[player].slot1`

### _rollLootboxBoons (private) — L1403
- delegatecall: **GAME_BOON_MODULE.checkAndClearExpiredBoon** (L1418) — **NESTED**
- revert: `E()` if `!okClr` (L1421)
- internal: `_simulatedDayIndex`†, `_lazyPassPriceForLevel`, `_isDecimatorWindow`, `_boonPoolStats`, `_boonFromRoll`, `_applyBoon`
- reads `boonPacked[player]`, `mintPacked_[player]`, `deityPassOwners.length`

### _settleLootboxRoll (private) — L1321
- internal: `PriceLookupLib.priceForLevel`, `_resolveLootboxRoll`, `_queueTickets`†
- external: **coinflip.creditFlip** (L1374), **wwxrp.mintPrize** (cold-bust consolation L1369)
- `_queueTickets`† → reverts + writes (see §2/§4)

### _resolveLootboxRoll (private) — L1965
- internal: `_lootboxTicketCount`, `_lootboxDgnrsReward`, `_creditDgnrsReward`, `_largeFlipOut`, `_ticketBudget`, `_ticketVarianceBps`, `EntropyLib.hash2`, spin dispatchers
- delegatecall: **GAME_DEGENERETTE_MODULE** via `_callWwxrpSpin`/`_callFlipSpins`/`_callEthSpin` — **NESTED**
- external: **dgnrs.poolBalance** (via `_lootboxDgnrsReward` L2257), **dgnrs.transferFromPool** (via `_creditDgnrsReward` L2273)

### _callWwxrpSpin / _callFlipSpins / _callEthSpin (private) — L2092/L2111/L2130
- delegatecall: **GAME_DEGENERETTE_MODULE.{resolveWwxrpSpinFromBox|resolveFlipSpinsFromBox|resolveEthSpinFromBox}** — **NESTED**
- revert: `E()` if `!ok` (L2107/L2126/L2145)

### _applyBoon (private) — L1705
- external: **IDegenerusQuests.awardQuestStreakShield** (L1845, BOON_QUEST_SHIELD path)
- internal: `_activateWhalePass`, tier helpers†
- **writes `boonPacked[player].slot0`/`.slot1`** (many sites — packed boon fields), **`whalePassClaims[player]`** (via `_activateWhalePass` L1489)

### _creditDgnrsReward (private) — L2271
- external: **dgnrs.transferFromPool** (L2273)

### _activateWhalePass (private) — L1486
- **writes `whalePassClaims[player] += 1`** (L1489)

### _applyEvMultiplierWithCap (private) — L474
- internal: `_lootboxEvUsedFor`†, `_setLootboxEvUsedFor`†
- **writes `lootboxEvCapPacked[player]`** (L503, packed level-window)

† = helper inherited from `DegenerusGameStorage` (executes inside this slice's frames).

---

## 2. REVERT-SITE INVENTORY

| fn:line | trigger | error | class |
|---|---|---|---|
| `openBox`:607 | neither leg queued at index for player | `E()` | TRANSIENT (per-call arg; other indices/players proceed) |
| `_openLootBoxLegWith`:545 | lootbox queued but `rngWord==0` | `RngNotReady` | **PERMANENT-CANDIDATE** (manual `openBox`/`_openLootBoxLeg`) — TRANSIENT IN SWEEP: `openHumanBoxes` pre-gates `word!=0` (L682 break) so the auto-open path never hits it; resolves once word lands |
| `_openBoxBoth`:631 | presale leg queued but `rngWord==0` | `RngNotReady` | TRANSIENT (manual path; resolves when word lands) |
| `resolveRedemptionLootbox`:927 | `msg.sender != SDGNRS` | `E()` | TRANSIENT (access gate) |
| `resolveRedemptionLootbox`:931 | `msg.value > amount` | `E()` | TRANSIENT (caller-controlled funding) |
| `resolveRedemptionLootbox`:935 | `steth.transferFrom` returns false | `E()` | TRANSIENT to advanceGame (off-spine sDGNRS claim); reverts the CLAIM tx — callee-revert risk (see §risk) |
| `creditRedemptionDirect`:1005 | `msg.sender != SDGNRS` | `E()` | TRANSIENT |
| `creditRedemptionDirect`:1006 | `msg.value > amount` | `E()` | TRANSIENT |
| `creditRedemptionDirect`:1011 | `steth.transferFrom` returns false | `E()` | TRANSIENT (claim tx); callee-revert risk |
| `issueDeityBoon`:1133 | deity/recipient zero | `E()` | TRANSIENT |
| `issueDeityBoon`:1134 | deity == recipient | `E()` | TRANSIENT |
| `issueDeityBoon`:1135 | slot >= 3 | `E()` | TRANSIENT |
| `issueDeityBoon`:1136 | deity lacks deity pass | `E()` | TRANSIENT |
| `issueDeityBoon`:1140 | `rngWordByDay[day]==0` | `E()` | TRANSIENT (off-spine; deity feature only — no advanceGame coupling) |
| `issueDeityBoon`:1147 | recipient already got boon today | `E()` | TRANSIENT |
| `issueDeityBoon`:1150 | slot already used today | `E()` | TRANSIENT |
| `_resolveLootboxCommon`:1284 | `consumeActivityBoon` delegatecall returns `!okAct` | `E()` | **PERMANENT-CANDIDATE** — on the open/resolve column; bubbles into `openHumanBoxes`/`resolveLootboxDirect`/`resolveAfkingBox`/`resolveRedemptionLootbox`. A revert in BoonModule wedges every box that reaches this branch (gated: only boxes whose owner has a pending activity bonus). See §nested. |
| `_rollLootboxBoons`:1421 | `checkAndClearExpiredBoon` delegatecall returns `!okClr` | `E()` | **PERMANENT-CANDIDATE** — same column; gated: only boxes whose owner holds a non-zero boon slot. |
| `_callWwxrpSpin`:2107 | `resolveWwxrpSpinFromBox` delegatecall returns `!ok` | `E()` | **PERMANENT-CANDIDATE** — on the open/resolve column; Degenerette spin failure bubbles to the box open. |
| `_callFlipSpins`:2126 | `resolveFlipSpinsFromBox` returns `!ok` | `E()` | **PERMANENT-CANDIDATE** — same column. |
| `_callEthSpin`:2145 | `resolveEthSpinFromBox` returns `!ok` | `E()` | **PERMANENT-CANDIDATE** — same column (direct-open boxes only). |
| `_queueTickets`†:618 | `_livenessTriggered()` true | `E()` | gated OUT of the sweep (`openHumanBoxes`:659 returns 0 if `_livenessTriggered()`); on `resolveLootboxDirect`/`resolveAfkingBox`/redemption it can revert if liveness fired — TRANSIENT to advanceGame (those are off-spine claim/recirc paths), but **PERMANENT-CANDIDATE for those claims** post-liveness. |
| `_queueTickets`†:621 | far-future + `rngLockedFlag` + !bypass | `RngLocked` | same as above (sweep entry-gate excludes `rngLockedFlag`; auto-open never hits it). On direct/redemption/afking far-future rolls during an RNG lock: reverts that claim — TRANSIENT to advanceGame. |
| checked-arith (implicit) | `claimablePool += uint128(amount)` (L1014), `prizePool* + uint128(amount)` (L943/L946) | Panic 0x11 overflow | TRANSIENT-by-construction (uint128 pools bounded « 2^128); not reachable in practice |

Notes:
- The openHumanBoxes SWEEP body is engineered non-reverting: the two revert sources on the open path (`rngLockedFlag`, `_livenessTriggered`) are hoisted to the L659 entry-gate, and the per-index `word!=0` gate (L682) excludes `RngNotReady`. The ONLY residual revert reachable inside the sweep loop is a sub-module delegatecall failure (the four `E()` PERMANENT-CANDIDATEs above) — if a BoonModule/DegeneretteModule delegatecall ever reverts for a ready box, that revert bubbles out of `openHumanBoxes` and can wedge the permissionless box-open sweep (the cursor never advances past the offending entry).
- None of these revert sites is on the `advanceGame`/`gameOver` finalization spine itself; `openHumanBoxes` is a *separate* permissionless bounty tx. A wedge here bricks box opening, not advanceGame progression. (The terminal-jackpot liveness control already short-circuits the sweep.)

---

## 3. LOOP INVENTORY

| fn:line | bound expression | per-iteration storage/gas | class |
|---|---|---|---|
| `openHumanBoxes` outer `while`:675 | `idx <= finalized && steps < budget` | per index: SLOAD `lootboxRngWordByIndex[idx]`, `boxPlayers[idx].length` | **BOUNDED** by `budget` (caller-passed `steps` cap; each index visit costs a step) |
| `openHumanBoxes` inner `while`:686 | `cur < qlen && steps < budget` | per player: SLOAD `lootboxEth`, `presaleBoxEth`; on open: full `_openLootBoxLegWith`/`_resolvePresaleBox` (writes + external calls) | **BOUNDED** by `budget` (shared `steps` counter); `boxPlayers[idx]` length is input/state-sized but the `steps < budget` cap and persistent `(boxCursorIndex, boxCursor)` make per-tx cost bounded |
| `resolveRedemptionLootbox`:951 `while (remaining != 0)` | `ceil(amount / 5 ether)` | per chunk: full `_resolveRedemptionChunk` (cap RMW, `_resolveLootboxCommon` w/ delegatecalls + external calls), `EntropyLib.hash1` | **UNBOUNDED/INPUT-SIZED** — iteration count = `amount/5e18`; `amount` is the redemption value (sDGNRS-burn-sized). No per-call budget cap. See §unbounded. |
| `_resolveLootboxCommon`:(no loop) | — | — | (split runs roll twice, not a loop) |
| `_lazyPassPriceForLevel`†:2288 `for i<10` | constant 10 | `PriceLookupLib.priceForLevel` (pure) | **BOUNDED** (fixed 10) |
| `_boonFromRoll`:1638.. | linear cursor scan, fixed weight count | pure arithmetic | **BOUNDED** (constant boon-type count) |
| `_queueTickets`†:(no loop) | — | — | — |

(`_queueTicketRange`† loops over `numLevels` but is NOT reached from this slice — whale-pass materialization is deferred to WhaleModule.claimWhalePass, out of slice.)

---

## 4. DELEGATECALL STORAGE-WRITE INVENTORY (Game slots written by this module)

Precise declared names. Packed-slot writes flagged with their key (offset/level/day).

| write site | storage var (declared) | packing / key |
|---|---|---|
| `_openLootBoxLegWith`:579 | `lootboxEth[index][player] = 0` | full-word clear of packed [amount\|adj\|score\|distress], keyed by (index, player) |
| `_openBoxBoth`:632, `openHumanBoxes`:707 | `presaleBoxEth[index][player] = 0` | full-word dequeue, keyed by (index, player) |
| `openHumanBoxes`:722 | `boxCursorIndex` | sweep cursor (own slot, uint48) |
| `openHumanBoxes`:723 | `boxCursor` | sweep cursor (own slot, uint48) |
| `openHumanBoxes`:728 | `presaleDrained = true` | **PACKED slot-0 bool** [29:30] — aliases `rngLockedFlag`, `level`, `claimablePool`, `boxCursor*`? NO (those are separate slots) — but slot-0 shares `presaleOver`/`presaleDrained`/etc.; one-way latch |
| `resolveRedemptionLootbox`:943 | `prizePoolPendingPacked` (frozen branch) | PACKED [next(128)\|future(128)], `_setPendingPools` |
| `resolveRedemptionLootbox`:946 | `prizePoolsPacked` (live branch) | PACKED [next(128)\|future(128)], `_setPrizePools` |
| `creditRedemptionDirect`:936 (via `_creditClaimable`) | `balancesPacked[player]` | PACKED [claimable(low128)\|afking(high128)], keyed by player — writes the LOW (claimable) half |
| `creditRedemptionDirect`:1014 | `claimablePool += amount` | **PACKED slot field** [16:32] uint128 (solvency aggregate); paired-credit invariant |
| `_applyEvMultiplierWithCap`:503 (via `_setLootboxEvUsedFor`) | `lootboxEvCapPacked[player]` | **PACKED, keyed by LEVEL window** — two 88-bit windows {used(64)+level(24)}; write targets the window stamped to `currentLevel` (else evicts smaller-level window). Aliasing-relevant: human-buy write (level+1) vs open write (currentLevel) share this slot. |
| `_presaleBoxDgnrsReward`:826 | `presaleBoxDgnrsPoolStart` | own slot uint256 (snapshot-once latch) |
| `issueDeityBoon`:1151 | `deityBoonPacked[deity]` | **PACKED, keyed by DAY** [0:24)=day, [24:32)=used-slot mask; day-roll re-stamps |
| `issueDeityBoon`:1154 | `deityBoonRecipientDay[recipient]` | own slot uint24, keyed by recipient+day |
| `_activateWhalePass`:1489 | `whalePassClaims[player] += 1` | own slot uint256 counter, keyed by player |
| `_queueTickets`†:629/634 | `ticketQueue[wk]` (push), `ticketsOwedPacked[wk][buyer]` | **PACKED, keyed by LEVEL** wk=`_tqWriteKey`/`_tqFarFutureKey(targetLevel)`; ticketsOwedPacked = [owed(32)<<8 \| rem(8)], keyed (wk, buyer) |
| `_applyBoon`:1732 | `boonPacked[player].slot0` (coinflip tier/day fields) | **PACKED, keyed by FIELD-SHIFT**: BP_COINFLIP_TIER/DAY, BP_DEITY_COINFLIP_DAY |
| `_applyBoon`:1756 | `boonPacked[player].slot0` (lootbox-boost) | PACKED: BP_LOOTBOX_TIER/DAY, BP_DEITY_LOOTBOX_DAY |
| `_applyBoon`:1785 | `boonPacked[player].slot0` (purchase) | PACKED: BP_PURCHASE_TIER/DAY, BP_DEITY_PURCHASE_DAY |
| `_applyBoon`:1811 | `boonPacked[player].slot0` (decimator) | PACKED: BP_DECIMATOR_TIER, BP_DEITY_DECIMATOR_DAY |
| `_applyBoon`:1836 | `boonPacked[player].slot0` (whale-discount) | PACKED: BP_WHALE_TIER/DAY, BP_DEITY_WHALE_DAY |
| `_applyBoon`:1867 | `boonPacked[player].slot1` (activity) | PACKED: BP_ACTIVITY_PENDING/DAY, BP_DEITY_ACTIVITY_DAY |
| `_applyBoon`:1890 | `boonPacked[player].slot1` (deity-pass) | PACKED: BP_DEITY_PASS_TIER/DAY, BP_DEITY_DEITY_PASS_DAY |
| `_applyBoon`:1932 | `boonPacked[player].slot1` (lazy-pass) | PACKED: BP_LAZY_PASS_TIER/DAY, BP_DEITY_LAZY_PASS_DAY |

External-call-driven state (NOT Game storage — written in callee contracts, listed for completeness): `coinflip.creditFlip` (FLIP credit), `dgnrs.transferFromPool` (DGNRS pool→player), `wwxrp.mintPrize`, `IDegenerusQuests.awardQuestStreakShield`. The Degenerette spin delegatecalls write GAME storage in the DegenerusGameDegeneretteModule slice (out of this slice — flagged as nested-delegatecall dispatch).

---

## SYNTHESIS POINTERS (418-425)

- The redemption 5-ETH `while` (L951) is the only INPUT-SIZED loop in the slice with no per-tx budget cap — iteration count scales with the sDGNRS gambling-burn `amount`. Each iteration carries a full `_resolveLootboxCommon` (two module delegatecalls + several external CALLs). Gas-brick consideration for a very large single redemption claim (off the advanceGame spine, but bricks that claimant's claim if it exceeds block gas).
- Four sub-module delegatecall revert-bubbles (`E()` at L1284/L1421/L2107/L2126/L2145) are the only revert sources reachable INSIDE the engineered-non-reverting `openHumanBoxes` sweep loop. A persistent revert from BoonModule or DegeneretteModule on a ready box wedges the permissionless box-open cursor.
- All Boon/Degenerette dispatches are NESTED delegatecalls (Game→Lootbox→Boon/Degenerette), msg.value preserved; `resolveLootboxDirect` is itself `payable` and reached via the payable redemption ETH-spin recirc — a non-payable guard there would brick the claim (by-design payable).
- Packed-slot aliasing hotspots: `lootboxEvCapPacked[player]` (level-window, written by both buy and open at different levels), `boonPacked[player].slot0/slot1` (field-shift), `deityBoonPacked[deity]` (day-keyed), `ticketsOwedPacked[wk][buyer]` (level-keyed via `_queueTickets`), slot-0 `presaleDrained` latch.
