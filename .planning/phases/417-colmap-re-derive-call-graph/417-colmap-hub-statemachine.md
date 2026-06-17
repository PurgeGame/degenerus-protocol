# Column Map — HUB slice: advanceGame + VRF + gameOver (DegenerusGame.sol)

Subject tree: frozen `0dd445a6`. File: `contracts/DegenerusGame.sol` (2485 lines).
Scope: the CORE STATE MACHINE entrypoints that live in `DegenerusGame.sol` plus the
inherited helpers they reach (`DegenerusGameStorage.sol`, `DegenerusGameMintStreakUtils.sol`).

> CRITICAL ARCHITECTURE NOTE — the actual state-machine BODY (`advanceGame` loop, `rngGate`,
> `_requestRng`/`_unlockRng`, `handleGameOverDrain`, terminal jackpot/decimator dispatch) is
> NOT in this file. `DegenerusGame.sol` exposes these as **thin `delegatecall(msg.data)` stubs**
> into `GAME_ADVANCE_MODULE` / `GAME_GAMEOVER_MODULE` / `GAME_JACKPOT_MODULE` /
> `GAME_DECIMATOR_MODULE`. Those bodies are mapped by the AdvanceModule / GameOverModule /
> Jackpot / Decimator slices. This slice maps the HUB **dispatch surface**: the stubs, their
> bubble-up reverts, the in-Game liveness/claim/queue helpers, and every revert/loop reachable
> here. The synthesizer must JOIN this against the AdvanceModule + GameOverModule slices.

---

## 1. CALL GRAPH (column-reachable HUB functions in DegenerusGame.sol)

Legend: `DC` = delegatecall; `DC(msg.data)` = raw calldata-forward delegatecall (selector-preserving);
`X→` = synchronous external call to FLIP/Coinflip/Vault/sDGNRS/Affiliate/COIN/stETH.

### Core advance / VRF stubs (all `DC(msg.data)` into GAME_ADVANCE_MODULE)
- **`advanceGame()`** (279) → `DC(msg.data)` GAME_ADVANCE_MODULE; on `!ok` → `_revertDelegate`; `abi.decode(data,(uint8))`.
  - This is THE spine entry. Everything (rngGate, ticket batches, phase transitions, gameOver path) executes inside the module under this Game's storage.
- **`wireVrf(address,uint256,bytes32)`** (302) → `DC(msg.data)` GAME_ADVANCE_MODULE.
- **`updateVrfCoordinatorAndSub(address,uint256,bytes32)`** (1776) → `DC(msg.data)` GAME_ADVANCE_MODULE. (emergency VRF rotation; ADMIN gate is in module body.)
- **`requestLootboxRng()`** (1792) → `DC(msg.data)` GAME_ADVANCE_MODULE.
- **`retryLootboxRng()`** (1804) → `DC(msg.data)` GAME_ADVANCE_MODULE. (the stalled mid-day lootbox-RNG retry path.)
- **`rawFulfillRandomWords(uint256,uint256[])`** (1856) → `DC(msg.data)` GAME_ADVANCE_MODULE. (Chainlink VRF callback; coordinator-only gate + nudge application live in module body.)

### Self-call terminal-finalization dispatch (gameOver-reachable)
- **`runDecimatorJackpot(uint256,uint24,uint256)`** (991) — gate `msg.sender==address(this)` → `DC(msg.data)` GAME_DECIMATOR_MODULE; `data.length==0 → E()`; decode uint256.
- **`runBafJackpot(uint256,uint24,uint256)`** (1013) — onlySelf → `DC(msg.data)` GAME_JACKPOT_MODULE; len-guard; decode.
- **`runTerminalDecimatorJackpot(uint256,uint24,uint256)`** (1068) — onlySelf → `DC(msg.data)` GAME_DECIMATOR_MODULE; len-guard; decode. (Reached from `handleGameOverDrain` self-call.)
- **`runTerminalJackpot(uint256,uint24,uint256)`** (1099) — onlySelf → `DC(msg.data)` GAME_JACKPOT_MODULE; len-guard; decode. (x00-level terminal jackpot; updates claimablePool internally.)
- **`emitDailyWinningTraits(uint24,uint256,uint24)`** (1121) — onlySelf → `DC(msg.data)` GAME_JACKPOT_MODULE.
- `recordDecBurn` (968), `recordTerminalDecBurn` (1038), `boostTerminalDecimator` (1053), `claimDecimatorJackpot[Many]` (1138/1150), `claimTerminalDecimatorJackpot` (1164) — all `DC` GAME_DECIMATOR_MODULE (gating in body). Decimator claim/record surface, gameOver-adjacent.

### Liveness / discovery helpers (in-Game, read-only; used by keepers + advance gate)
- **`advanceDue()`** (1386) → internal: `_simulatedDayIndex()`, reads `dailyIdx`, `ticketsFullyProcessed`, `level`, `jackpotPhaseFlag`, `lastPurchaseDay`, `rngLockedFlag`, `ticketQueue[_tqReadKey(...)].length`. No external call. O(1).
- **`boxesPending()`** (1412) → internal `_livenessTriggered()` (which `X→ none`; pure day-math + rngRequestTime), `_lrRead(LR_INDEX...)`, reads `boxCursorIndex`,`boxCursor`,`lootboxRngWordByIndex[idx]`,`boxPlayers[idx].length`. O(1).
- **`boxIndexComplete(uint48)`** (1428) → reads `boxCursorIndex`. O(1).
- **`bountyEligible(address)`** (1403) → `_bountyEligible(who)` →  on the cold path `X→ Vault.isVaultOwner(who)` (MintStreakUtils:79). Reads `dailyIdx`,`mintPacked_[who]`,`level`,`_subOf[who]`.
- **`livenessTriggered()`** (2053) → `_livenessTriggered()`. No external call.
- **`currentDayView()`** (522), **`rngWordForDay`** (2089), **`rngLocked`** (2096), **`isRngFulfilled`** (2102), **`lastVrfProcessed`** (2108), **`gameOverTimestamp`** (2045), **`isFinalSwept`** (2040), **`jackpotPhase`** (2129), **`jackpotCompressionTier`** (2124), **`terminalDecWindow`** (1085) — pure reads of state-machine flags; no calls, no loops.

### Permissionless work / open valves (HUB-adjacent, reachable by keepers)
- **`mintFlip()`** (376) → `DC(msg.data)` GAME_AFKING_MODULE. (the permissionless advance→afking-box router + bounty.)
- **`openBoxes(uint256 maxCount)`** (1442) → `DC` GAME_AFKING_MODULE `drainAfkingBoxes(maxCount)` (decode uint256), then if `openedAfking<maxCount` → `DC` GAME_LOOTBOX_MODULE `openHumanBoxes(remaining)` (decode uint256). Two sequential delegatecalls; no loop in THIS frame (loops live in modules).
- **`degeneretteResolve(address[],uint64[])`** (1339) → **has a do-while loop**; per-item `this._degeneretteResolveBet(...)` (external self-call wrapped in try/catch); on `successCount>=3` → `X→ coinflip.creditFlip(msg.sender, 1e18)`.
- **`_degeneretteResolveBet(address,uint64)`** (1479) — onlySelf external → `DC` GAME_DEGENERETTE_MODULE `resolveBets`.

### Claim / afking-funding (in-Game; touch claimablePool + gameOver gate)
- **`claimWinnings(address)`** (1209) → `_resolvePlayer` → `_claimWinningsInternal(player,false)` → then `DC` GAME_AFKING_MODULE `maybeCurse(player)`.
- **`claimWinningsStethFirst()`** (1224) — `msg.sender==VAULT` gate → `_claimWinningsInternal(msg.sender,true)`.
- **`_claimWinningsInternal(player,stethFirst)`** (1229) → `_goRead(GO_SWEPT)`, `_claimableOf`, `_afkingOf` (gated on `gameOver`), `_debitClaimableAndAfking`, `claimablePool -= payout` (checked), then `_payoutWithEthFallback` OR `_payoutWithStethFallback`.
  - `_payoutWithStethFallback` (1888): reads balances, `_transferSteth` (→ `X→ steth.transfer`/`steth.approve`+`dgnrs.depositSteth` for SDGNRS), then `X→ to.call{value}` LAST (CEI).
  - `_payoutWithEthFallback` (1922): `_transferSteth` first, then `X→ to.call{value:remaining}`.
- **`depositAfkingFunding(address)`** payable (1263) → `_creditAfkingValue` (credits afking half + `claimablePool +=`).
- **`withdrawAfkingFunding(uint256)`** (1275) → `_goRead(GO_SWEPT)` guard, `_afkingOf`, `_debitAfking`, `claimablePool -= amount` (checked), `X→ msg.sender.call{value}`.
- **`receive()`** payable (2481) → `if (gameOver) revert E()`; else `_creditAfkingValue(msg.sender,msg.value)`.

### Admin liquidity / redemption-reserve (touch solvency invariant)
- **`adminSwapEthForStEth`** (1705) → `X→ steth.balanceOf`, `steth.transfer`.
- **`adminStakeEthForStEth`** (1726) → `X→ Vault.isVaultOwner`, `_claimableOf`×2, `X→ steth.submit{value}` (try/catch).
- **`pullRedemptionReserve(uint256)`** (1572) — `msg.sender==SDGNRS` gate → `_claimableOf(SDGNRS)`, `_debitClaimable`, `claimablePool -= amount`, `X→ SDGNRS.call{value}` (ETH leg) OR `X→ steth.balanceOf(SDGNRS)` (stETH leg) else `revert E()`.
- **`setLootboxRngThreshold(uint256)`** (530) → `X→ Vault.isVaultOwner`, `_lrRead`/`_lrWrite(LR_THRESHOLD...)`.
- **`payCoinflipBountyDgnrs`** (453) → COIN/COINFLIP gate, `X→ dgnrs.poolBalance`, `dgnrs.transferFromPool`.

### Constructor-path loop (deploy-time, not column-reachable post-deploy)
- **`initPerpetualTickets()`** (216) — SDGNRS/VAULT-only → **for-loop i=1..100** calling `_queueTickets(who,i,16,false)`.

---

## 2. REVERT-SITE INVENTORY

Classification: **TRANSIENT** = caller/another actor can still make progress (gating, bad-input, competition).
**PERMANENT-CANDIDATE** = could wedge advanceGame progress or gameOver finalization forever (a revert on the spine, OR a callee revert that bubbles through a `DC(msg.data)` stub).

| fn:line | trigger | error | class |
|---|---|---|---|
| `advanceGame:283` | module delegatecall returns `!ok` | bubbled (module reason) via `_revertDelegate` | **PERMANENT-CANDIDATE** — any revert inside GAME_ADVANCE_MODULE (rngGate / batch / drain / jackpot) bubbles here; if a state combo makes the module always revert, advanceGame is wedged. Join with AdvanceModule slice. |
| `_revertDelegate:949` | empty `reason` from any failed DC | `E()` | inherits class of caller stub. For `advanceGame`/gameOver-finalization stubs = PERMANENT-CANDIDATE; for claim/mint stubs = TRANSIENT. |
| `wireVrf:306` | module `!ok` | bubbled | TRANSIENT (deploy-time admin). |
| `updateVrfCoordinatorAndSub:1784` | module `!ok` (e.g. non-ADMIN) | bubbled | TRANSIENT — but this is the VRF-stall RECOVERY lever; if it itself reverts under a needed rotation, recovery is blocked → see riskNotes. |
| `requestLootboxRng:1796` / `retryLootboxRng:1808` | module `!ok` | bubbled | TRANSIENT (lootbox RNG side path; not the daily spine). |
| `rawFulfillRandomWords:1863` | module `!ok` (coordinator-gate fail, stale requestId, nudge math) | bubbled | **PERMANENT-CANDIDATE** — if the VRF callback ALWAYS reverts in the module, no word lands, rngLock never clears → daily spine stalls until `_VRF_GRACE_PERIOD` liveness bailout. Join with AdvanceModule.rawFulfillRandomWords body. |
| `runTerminalJackpot:1104` / `:1108` / `:1109` | `!=address(this)` / module `!ok` / empty data | `E()` / bubbled | **PERMANENT-CANDIDATE** — self-called from gameOver finalization (handleGameOverDrain). A revert here wedges terminal-jackpot payout. Join GameOver+Jackpot slices. |
| `runTerminalDecimatorJackpot:1073/77/78` | onlySelf / module `!ok` / empty | `E()` / bubbled | **PERMANENT-CANDIDATE** — terminal decimator finalization. |
| `runDecimatorJackpot:996/1000/1001` | onlySelf / `!ok` / empty | `E()` / bubbled | PERMANENT-CANDIDATE (self-called from advance orchestration at x00 levels). |
| `runBafJackpot:1018/1022/1023` | onlySelf / `!ok` / empty | `E()` / bubbled | PERMANENT-CANDIDATE (self-called from advance orchestration at L%100==0). |
| `emitDailyWinningTraits:1126/1130` | onlySelf / `!ok` | `E()` / bubbled | PERMANENT-CANDIDATE (self-called in advance at purchaseLevel==1). |
| `_queueTickets:618` (Storage) | `_livenessTriggered()` true | `E()` | TRANSIENT-by-intent — INTENTIONAL block of new tickets once liveness fired (anti-manipulation). NOT a wedge of advance/finalize: it only stops NEW queueing; the drain path still finalizes. |
| `_queueTickets:621` (Storage) | far-future + `rngLockedFlag` + !bypass | `RngLocked()` | TRANSIENT (retry after unlock). |
| `initPerpetualTickets:218` | caller not SDGNRS/VAULT | `E()` | TRANSIENT (deploy-time access gate). |
| `_claimWinningsInternal:1230` | `GO_SWEPT != 0` | `E()` | TRANSIENT-terminal — post-final-sweep claims are intentionally closed (funds forfeited). Does NOT wedge finalization (sweep already done). |
| `_claimWinningsInternal:1237` | `amount<=1 && afking==0` | `E()` | TRANSIENT (nothing to claim). |
| `_claimWinningsInternal:1248` | `claimablePool -= payout` underflow | checked-arith panic | TRANSIENT per-player; an accounting bug would revert the individual claim, not the spine. |
| `_debitClaimableAndAfking:973/974` (Storage) | low<claimable or high<afking | `E()` | TRANSIENT (per-player). |
| `_payoutWithStethFallback:1914` | final ETH `to.call` `!ok` | `E()` | TRANSIENT — a hostile/contract `to` that rejects ETH blocks ONLY its own claim (pull pattern). Does NOT wedge spine. |
| `_payoutWithEthFallback:1933/1935` | `ethBal<remaining` / `to.call !ok` | `E()` | TRANSIENT (vault-only path). |
| `_transferSteth:1876/1880` | `steth.approve`/`transfer` false | `E()` | TRANSIENT (per-claim; external token). |
| `withdrawAfkingFunding:1276/1279/1283` | GO_SWEPT / amount>bal / `call !ok` | `E()` | TRANSIENT. CEI: GO_SWEPT guard is line-1. |
| `depositAfkingFunding:1264` | `player==address(0)` | `E()` | TRANSIENT. |
| `receive:2482` | `gameOver` true | `E()` | TRANSIENT-by-design (bare sends blocked post-gameOver). |
| `pullRedemptionReserve:1573/1585/1599` | !SDGNRS / ETH `call !ok` / neither-leg | `E()` | TRANSIENT (sDGNRS-side; fail-closed). |
| `setLootboxRngThreshold:531/532` | !vaultOwner / zero | `E()` | TRANSIENT. |
| `adminSwapEthForStEth:1709-1715` | !ADMIN / zero / value-mismatch / low stBal / transfer-false | `E()` | TRANSIENT. |
| `adminStakeEthForStEth:1727/1728/1731/1738/1740/1744` | !vaultOwner / zero / low bal / reserve-dip / stakeable / submit-catch | `E()` | TRANSIENT. |
| `degeneretteResolve:1344` | `len==0` or length mismatch | `E()` | TRANSIENT (bad input). |
| `degeneretteResolve:1351` | probe item 0 slot==0 (competitor won) | `BatchAlreadyTaken()` | TRANSIENT (loser-gas cap; intended). |
| `degeneretteResolve:1378` | `totalResolved==0` | `NoWork()` | TRANSIENT. |
| `_degeneretteResolveBet:1480` | `!=address(this)` | `E()` | TRANSIENT (onlySelf wrapper). |
| `payCoinflipBountyDgnrs:461` | !COIN && !COINFLIP | `E()` | TRANSIENT. |
| `runDecimatorJackpot/etc onlySelf:996` etc. | external caller | `E()` | TRANSIENT for an external attacker (cannot call); the self-call path is the PERMANENT-CANDIDATE noted above. |
| `_resolvePlayer→_requireApproved:505` | not self & not approved | `NotApproved()` | TRANSIENT. |
| `setOperatorApproval:487` | `operator==address(0)` | `E()` | TRANSIENT. |
| `consumeCoinflipBoon:833` / `consumeDecimatorBoon:849` / `drainAffiliateBase:407` | caller gate / empty data | `E()` | TRANSIENT (creditor-side). |
| `_currentNudgeCost` (reverseFlip path) | `reverseFlip:1818` rngLockedFlag | `RngLocked()` | TRANSIENT (nudge blocked during lock; intended). |

---

## 3. LOOP INVENTORY

| fn:line | iteration-count bound | per-iter storage/gas | class |
|---|---|---|---|
| `initPerpetualTickets:219` | fixed `i=1..100` (100 iters) | `_queueTickets` → 1 `ticketQueue[wk].push` + 1 `ticketsOwedPacked[wk][buyer]` SSTORE per level + `_livenessTriggered()` (read) + emit | **BOUNDED** (constant 100; deploy-time, split out of constructor for gas-cap). Not column-reachable post-deploy. |
| `degeneretteResolve:1356` (do-while) | `i` up to `players.length` (caller-supplied) | per-iter: 1 `degeneretteBets[..]` SLOAD + 1 external `this._degeneretteResolveBet` (try/catch, each = a full DC into Degenerette module) | **UNBOUNDED / INPUT-SIZED** — bound = `players.length` chosen by caller; caller pays own gas, per-item isolation, no spine state. Self-DoS only. |
| `_currentNudgeCost:1838` (while) | `reversals` = `totalFlipReversals` | pure arithmetic (no SSTORE) | INPUT/STATE-SIZED but bounded by FLIP supply economics (each nudge burns ≥100 FLIP); cost is *=1.5 per iter. Not on spine. Off-frontier. |
| `afkingSnapshot:2270` (view) | `players.length` | 2 SLOAD/iter | INPUT-SIZED, view-only (no gas-brick risk to spine). |
| `sampleTraitTicketsAtLevel:2328` | `take<=4` | array read | BOUNDED. |
| `sampleFarFutureTickets:2349` | `s<10 && found<4` | keccak + queue SLOAD | BOUNDED (≤10). |
| `sampleFarFutureTickets:2371` | `i<found<=4` | mem | BOUNDED. |
| `getTickets:2409` (view) | `offset..end` (caller `limit`) | 1 SLOAD/iter | INPUT-SIZED, view-only. |
| `getDailyHeroWinner:2458/2460` (view) | fixed 4×8 | packed read | BOUNDED. |

> No unbounded loop exists in THIS file on the daily-advance spine. The advance loop's
> ticket-batch iteration lives in GAME_ADVANCE_MODULE (join that slice for the
> batch-size bound / 16.7M ceiling analysis). The only INPUT-SIZED loops here are
> off-spine and self-gas-paid (degeneretteResolve, views).

---

## 4. DELEGATECALL STORAGE-WRITE INVENTORY (writes performed in THIS file's frame)

> The advance-spine stubs write NOTHING in the Game frame — they `DC(msg.data)` and the
> module writes land in Game storage (mapped by the AdvanceModule/GameOver slices). The
> writes BELOW are the ones executed directly in `DegenerusGame.sol` code (or its inherited
> internal helpers invoked from this file).

| writer fn:line | storage variable/field written | packed? key |
|---|---|---|
| `setOperatorApproval:488` | `operatorApprovals[msg.sender][operator]` | no |
| `_claimWinningsInternal:1247` → `_debitClaimableAndAfking:975` | `balancesPacked[player]` | **PACKED** — low128=claimable, high128=afking; debited per-player (key=player) |
| `_claimWinningsInternal:1248` | `claimablePool` (uint128) | no (solvency aggregate; checked `-=`) |
| `_creditAfkingValue:988/989` (from receive, depositAfkingFunding) | `balancesPacked[player]` (afking high half via `_creditAfking`), `claimablePool` | **PACKED** key=player |
| `withdrawAfkingFunding:1280/1281` → `_debitAfking:959` | `balancesPacked[msg.sender]` (high half), `claimablePool` | **PACKED** key=msg.sender |
| `pullRedemptionReserve:1582/1583` → `_debitClaimable:945` | `balancesPacked[SDGNRS]` (low half), `claimablePool` | **PACKED** key=SDGNRS |
| `setLootboxRngThreshold:538` → `_lrWrite(LR_THRESHOLD_SHIFT,LR_THRESHOLD_MASK)` | `lootboxRngPacked` (LR_THRESHOLD field) | **PACKED** key=offset LR_THRESHOLD_SHIFT |
| `reverseFlip:1826` | `totalFlipReversals` (uint64) | **PACKED** — co-resident with `lastVrfProcessedTimestamp` in one slot; masked RMW preserves the VRF timestamp (flagged: a careless write here could corrupt `lastVrfProcessedTimestamp`, which governance reads for stall detection) |
| `initPerpetualTickets:220` → `_queueTickets:629/634` | `ticketQueue[wk]` (push), `ticketsOwedPacked[wk][buyer]` | `ticketsOwedPacked` **PACKED** (owed<<8 \| rem); key=(level,buyer) |

> `claimablePool` is the cross-cutting solvency aggregate touched by 5 distinct paths here
> (claim, deposit, withdraw, redemption-reserve, plus the module credit paths). All `-=` are
> CHECKED; all `+=` use `uint128` casts. The synthesizer should treat `claimablePool` and the
> packed `balancesPacked[player]` (claimable|afking) as the aliasing-relevant hotspots for the
> solvency-invariant check.

---

## 5. NOTES FOR THE 418–425 HUNT

- The HUB is a **dispatch hub**: the real wedge surface is the set of `DC(msg.data)` stubs
  whose bubbled revert is PERMANENT-CANDIDATE — `advanceGame`, `rawFulfillRandomWords`, and the
  five onlySelf terminal-finalization stubs. A revert inside the corresponding module body that
  is *unconditional under some reachable state combo* would wedge the spine here. These MUST be
  cross-checked against the AdvanceModule + GameOverModule + Jackpot + Decimator slices.
- `_livenessTriggered()` is the designed anti-wedge bailout: after `_VRF_GRACE_PERIOD` (14 days)
  with `rngRequestTime != 0`, liveness fires and the gameOver/terminal-jackpot drain path opens
  even if the normal cycle is bricked. It is GATED OFF while `lastPurchaseDay || jackpotPhaseFlag`
  — the comment at MintStreakUtils/Storage explicitly flags the multi-call window between
  target-met and phase-transition-close as a place where a fire would deadlock; confirm
  `_handleGameOverPath` is unreachable in that window (AdvanceModule responsibility).
- `_queueTickets` reverts `E()` once liveness fires (anti-manipulation) — intended, but note any
  spine path that *requires* `_queueTickets` to succeed after liveness would wedge; the perpetual
  ticket re-queue (advance handles 101+) must be checked to not run on the post-liveness path.
- `reverseFlip` writes `totalFlipReversals` co-resident with `lastVrfProcessedTimestamp` — masked
  RMW; a regression that drops the mask would corrupt the governance stall-detection timestamp.
- `claimWinnings` post-`gameOver` lazily merges `_afkingOf(player)` into the payout (GAMEOVER-01).
  The GO_SWEPT guard (line-1 in claim + withdraw) closes the post-sweep double-spend; confirm the
  final sweep (GameOverModule) zeroes `claimablePool` so no underflow.
