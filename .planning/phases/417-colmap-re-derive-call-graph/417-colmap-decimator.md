# Column Map — Slice: Decimator + GameOver + PayoutUtils

Subject = frozen `contracts/` tree `0dd445a6`. Read-only enumeration.

Files:
- `contracts/modules/DegenerusGameDecimatorModule.sol` (regular + terminal decimator; via delegatecall in Game storage)
- `contracts/modules/DegenerusGameGameOverModule.sol` (gameover drain + 30-day final sweep; via delegatecall)
- `contracts/modules/DegenerusGamePayoutUtils.sol` (abstract base; box-proceeds + whale-pass-claim helpers)

Storage helpers cited live in `contracts/storage/DegenerusGameStorage.sol` (inherited). All three modules execute via DELEGATECALL from `DegenerusGame`, so every storage write lands in the GAME's slots.

DELEGATECALL dispatch facts (from `DegenerusGame.sol`):
- `runTerminalDecimatorJackpot(uint256,uint24,uint256)` Game stub @1068 → `delegatecall(msg.data)` to `GAME_DECIMATOR_MODULE` (raw msg.data forward).
- `runTerminalJackpot(uint256,uint24,uint256)` Game stub @1099 → `delegatecall(msg.data)` to `GAME_JACKPOT_MODULE` (raw msg.data forward, out of this slice).
- `claimDecimatorJackpot(address,uint24)` Game stub @1138, `claimDecimatorJackpotMany(address[],uint24)` @1150, `claimTerminalDecimatorJackpot()` @1164 → `delegatecall(msg.data)` to `GAME_DECIMATOR_MODULE`.
- `playerActivityScore(address)` Game @2215 is a LOCAL VIEW (no delegatecall); it calls `quests.effectiveBaseStreakAndAfking` externally. The module's `IDegenerusGame(address(this)).playerActivityScore(...)` is therefore a self-STATICCALL into the Game's own view, NOT a nested delegatecall.

---

## 1. CALL GRAPH (column-reachable functions in this slice)

### DegenerusGamePayoutUtils.sol (abstract base, inherited by Decimator)

| fn | internal calls | delegatecalls | sync external calls (FLIP/Coinflip/Vault/sDGNRS/Affiliate) |
|---|---|---|---|
| `_creditBoxProceeds` (19) | `_creditClaimable` ×2 | — | none (credits VAULT/SDGNRS as claimable bookkeeping; no call) |
| `_queueWhalePassClaimCore` (32) | `_creditClaimable` | — | none |

### DegenerusGameDecimatorModule.sol — regular decimator

| fn | internal calls | delegatecalls | sync external calls |
|---|---|---|---|
| `recordDecBurn` (142) ext, COIN-gated | `_decRemoveSubbucket`, `_decSubbucketFor`, `_decUpdateSubbucket` ×2, `_decEffectiveAmount` | — | none (msg.sender==COIN check only) |
| `runDecimatorJackpot` (224) ext, GAME-gated | `_decWinningSubbucket`, `_packDecWinningSubbucket` (loop), `_setFuturePrizePool` (not here) | — | none |
| `claimDecimatorJackpot` (293) ext, permissionless | `_decClaimableFromEntry`, `_claimDecimatorJackpotFor` | (transitively via `_awardDecimatorLootbox`) | none directly |
| `claimDecimatorJackpotMany` (325) ext, permissionless | `_decClaimableFromEntry` (loop), `_claimDecimatorJackpotFor` (loop), `_mintPriceInContext` | (transitively via `_awardDecimatorLootbox`) | **`coinflip.creditFlip(msg.sender, ...)` @365** (keeper bounty, post-loop, only if `!over && settled!=0`) |
| `decClaimable` (431) ext view | `_decClaimable` → `_decClaimableFromEntry`, `_unpackDecWinningSubbucket` | — | none |
| `_claimDecimatorJackpotFor` (385) priv | `_creditClaimable` (over-branch), `_creditDecJackpotClaimCore`, `_minScoreForBucket`, `_setFuturePrizePool`, `_getFuturePrizePool` | — | none directly (lootbox via `_creditDecJackpotClaimCore`) |
| `_creditDecJackpotClaimCore` (449) priv | `_creditClaimable`, `_awardDecimatorLootbox` | (via `_awardDecimatorLootbox`) | none |
| `_awardDecimatorLootbox` (645) priv | `_applyWhalePassStats`, `_queueTicketRange` | **NESTED delegatecall @669:** `GAME_LOOTBOX_MODULE.delegatecall(resolveLootboxDirect.selector,...)` | none directly (lootbox module may credit downstream) |
| `_decEffectiveAmount` (472) priv pure | — | — | none |
| `_decWinningSubbucket` (496) priv pure | — | — | none |
| `_packDecWinningSubbucket` (510) / `_unpackDecWinningSubbucket` (525) priv pure | — | — | none |
| `_decClaimableFromEntry` (541) priv view | `_unpackDecWinningSubbucket` | — | none |
| `_decClaimable` (568) internal view | `_decClaimableFromEntry` | — | none |
| `_decUpdateSubbucket` (595) / `_decRemoveSubbucket` (610) internal | — | — | none |
| `_decSubbucketFor` (629) priv pure | — | — | none |
| `_minScoreForBucket` (689) priv pure | — | — | none |
| `_mintPriceInContext` (376) priv view | `PriceLookupLib.priceForLevel` | — | none |

### DegenerusGameDecimatorModule.sol — terminal decimator

| fn | internal calls | delegatecalls | sync external calls |
|---|---|---|---|
| `recordTerminalDecBurn` (782) ext, COIN-gated | `_terminalDecDaysRemaining`, `_terminalDecBucket`, `_decEffectiveAmount`, `_terminalDecMultiplierBps`, `_decSubbucketFor` | — | **self-STATICCALL @793:** `IDegenerusGame(address(this)).playerActivityScore(player)` → Game view → `quests.effectiveBaseStreakAndAfking` (external to QUESTS) |
| `boostTerminalDecimator` (882) ext, permissionless (msg.sender self) | `_livenessTriggered`, `_terminalDecDaysRemaining`, `_effectiveQuestStreak`, `_terminalDecBoostFactorBps`, `_terminalDecBucket`, `_decSubbucketFor` | — | **self-STATICCALL @913:** `playerActivityScore` (→ QUESTS); `_effectiveQuestStreak` @897 also reads `quests.effectiveBaseStreakAndAfking` (external QUESTS) |
| `runTerminalDecimatorJackpot` (978) ext, GAME-gated | `_decWinningSubbucket` (loop), `_packDecWinningSubbucket` (loop) | — | none. **NOTE: this is itself reached via NESTED delegatecall** (GameOver `handleGameOverDrain` → `IDegenerusGame(address(this)).runTerminalDecimatorJackpot(...)` → Game stub @1068 → delegatecall to this module) |
| `claimTerminalDecimatorJackpot` (1042) ext, self-claim | `_consumeTerminalDecClaim`, `_creditClaimable` | — | none |
| `terminalDecClaimable` (1053) ext view | `_unpackDecWinningSubbucket` | — | none |
| `_consumeTerminalDecClaim` (1085) priv | `_unpackDecWinningSubbucket` | — | none |
| `_terminalDecBoostFactorBps` (953) / `_terminalDecMultiplierBps` (1124) / `_terminalDecBucket` (1133) priv pure | — | — | none |
| `_terminalDecDaysRemaining` (1147) priv view | `_simulatedDayIndex` (→ `GameTimeLib.currentDayIndex`) | — | none |

### DegenerusGameGameOverModule.sol

| fn | internal calls | delegatecalls | sync external calls |
|---|---|---|---|
| `handleGameOverDrain` (73) ext | `_goRead` ×2, `_goWrite` ×2, `_creditClaimable` (deity loop), `_setNextPrizePool`/`_setFuturePrizePool`/`_setCurrentPrizePool` | **NESTED self-delegatecalls** via Game stubs: `runTerminalDecimatorJackpot` @177 (→ Decimator module), `runTerminalJackpot` @191 (→ Jackpot module, out of slice) | `steth.balanceOf(this)` @78,157,165; `charityGameOver.burnAtGameOver()` @139 (GNRUS); `dgnrs.burnAtGameOver()` @139→@140 (sDGNRS); `flip.tombstoneAtGameOver()` @142 (FLIP/COIN) |
| `handleFinalSweep` (203) ext | `_goRead` ×3, `_goWrite`, `_claimableOf` ×3, `_debitClaimable` ×3, `_sendStethFirst` ×3 | — | `admin.shutdownVrf()` @220 (try/catch, ADMIN); `steth.balanceOf(this)` @223; (`_sendStethFirst` does steth.transfer + ETH `.call`) |
| `_sendStethFirst` (250) priv | — | — | `steth.transfer(to,...)` @253,257 (stETH); `payable(to).call{value}` @261 (ETH send to VAULT/SDGNRS/GNRUS) |

External-handle facts: `coinflip` (ICoinflip = COIN-side flip-credit ledger), `dgnrs` (IsDGNRS = sDGNRS), `quests` (IDegenerusQuests = QUESTS), `steth`, `admin`, `charityGameOver` (GNRUS), `flip` (COIN).

---

## 2. REVERT-SITE INVENTORY

| fn:line | trigger condition | error | classification |
|---|---|---|---|
| DecModule.recordDecBurn:149 | `msg.sender != COIN` | `OnlyCoin()` | TRANSIENT (access gate; coin-only burn path) |
| DecModule._decRemoveSubbucket:618 | `slotTotal < delta` (migration removes more than subbucket holds) | `E()` | PERMANENT-CANDIDATE — reached from `recordDecBurn` migration branch; if aggregate accounting ever desyncs from per-entry burn, the burn path reverts. NOT in advanceGame chain, but a recordDecBurn revert blocks all decimator burns at the level. Underflow-guard, not expected to fire. |
| DecModule.recordDecBurn:186 | `updated > uint192.max` → saturates (NO revert; clamps) | — | n/a (saturation, no revert) |
| DecModule.runDecimatorJackpot:229 | `msg.sender != GAME` | `OnlyGame()` | TRANSIENT (access gate) |
| DecModule.runDecimatorJackpot:233 | already snapshotted (`round.poolWei != 0`) → `return poolWei` | — | n/a (early return, idempotent; NOT a revert) |
| DecModule.runDecimatorJackpot:273 | `uint96(poolWei)` truncation if poolWei > uint96.max | implicit (unchecked cast, silent) | TRANSIENT (cast, no revert; poolWei is a fraction of contract balance, far below uint96) |
| DecModule.claimDecimatorJackpot:298 | `prizePoolFrozen` true | `E()` | TRANSIENT (claim deferred until unfreeze; advanceGame unfreezes — does not wedge the column) |
| DecModule.claimDecimatorJackpot:302 | `round.poolWei == 0` (no snapshot) | `DecClaimInactive()` | TRANSIENT (level not resolved / no winners) |
| DecModule.claimDecimatorJackpot:305 | `e.claimed != 0` | `DecAlreadyClaimed()` | TRANSIENT |
| DecModule.claimDecimatorJackpot:314 | `amountWei == 0` (not a winner) | `DecNotWinner()` | TRANSIENT |
| DecModule.claimDecimatorJackpotMany:329 | `prizePoolFrozen` true | `E()` | TRANSIENT |
| DecModule.claimDecimatorJackpotMany:333 | `round.poolWei == 0` | `DecClaimInactive()` | TRANSIENT (whole batch reverts but is a side claim path, not the column) |
| DecModule._creditDecJackpotClaimCore:462 | `claimablePool -= uint128(lootboxPortion)` underflow | arithmetic underflow (0.8 revert) | PERMANENT-CANDIDATE (off-column) — would revert the claim if claimablePool < lootboxPortion. Solvency-invariant dependent; not in advance/gameover chain. |
| DecModule._awardDecimatorLootbox:681 | nested delegatecall to LOOTBOX_MODULE `resolveLootboxDirect` failed | bubbles via `_revertDelegate` | PERMANENT-CANDIDATE (off-column, claim only) — a failing lootbox resolve reverts that one claim; does NOT touch advanceGame/gameover. |
| DecModule.recordTerminalDecBurn:787 | `msg.sender != COIN` | `OnlyCoin()` | TRANSIENT |
| DecModule.recordTerminalDecBurn:790 | `daysRemaining <= 7` | `TerminalDecDeadlinePassed()` | TRANSIENT (by-design 7-day cooldown; burns blocked near death) |
| DecModule.recordTerminalDecBurn:840/850 | totalBurn/weightedBurn saturate at uint80/uint88 (NO revert; clamp) | — | n/a |
| DecModule.recordTerminalDecBurn:855 | `terminalDecBucketBurnTotal[bucketKey] += weightedAmount` overflow | arithmetic (uint256, unreachable in practice) | TRANSIENT (uint256 aggregate; weightedAmount supply-bounded) |
| DecModule.boostTerminalDecimator:883 | `_livenessTriggered()` true (game-over window open) | `TerminalDecNotActive()` | TRANSIENT (boost only pre-liveness; by-design) |
| DecModule.boostTerminalDecimator:884 | `daysRemaining != 0` (not the deadline day) | `TerminalDecNotBoostable()` | TRANSIENT |
| DecModule.boostTerminalDecimator:892/895/898/901 | stale/empty entry, already boosted, zero streak, zero weight | `TerminalDecNotBoostable()` / `TerminalDecAlreadyBoosted()` | TRANSIENT (caller-specific eligibility) |
| DecModule.boostTerminalDecimator:942 | `terminalDecBucketBurnTotal[oldKey] -= oldWeighted` underflow (promotion path) | arithmetic underflow | PERMANENT-CANDIDATE (off-column) — would revert the boost if aggregate desyncs; bounded by conservation invariant (each entry's weight was added to oldKey at burn). Boost is off-column; failure only blocks that player's boost. |
| DecModule.runTerminalDecimatorJackpot:983 | `msg.sender != GAME` | `OnlyGame()` | TRANSIENT (but see GAMEOVER note — reached via self-delegatecall whose msg.sender IS the Game) |
| DecModule.runTerminalDecimatorJackpot:986 | already resolved (`lastTerminalDecClaimRound.lvl == lvl`) → return poolWei | — | n/a (idempotent early return) |
| DecModule.runTerminalDecimatorJackpot:1024 | `decBucketOffsetPacked[lvl + 1]` write — `lvl+1` overflow if lvl==uint24.max | arithmetic (uint24 add inside uint256 expr → actually widened; lvl is uint24 param) | PERMANENT-CANDIDATE (theoretical) — `lvl + 1` is computed in uint256 context (no truncation revert); DEC-ALIAS keying. Practically lvl never near uint24.max. |
| DecModule.runTerminalDecimatorJackpot:1028 | `uint96(poolWei)` / `uint128(totalWinnerBurn)` truncation | silent cast | TRANSIENT (no revert; supply-bounded) |
| DecModule.claimTerminalDecimatorJackpot → _consumeTerminalDecClaim:1089 | `lvl == 0` (no resolved round) | `TerminalDecNotActive()` | TRANSIENT |
| DecModule._consumeTerminalDecClaim:1092/1102/1105/1110 | stale entry / zero weight / wrong subbucket / zero totalBurn / zero amount | `TerminalDecNotWinner()` | TRANSIENT |
| GameOver.handleGameOverDrain:74 | `GO_JACKPOT_PAID != 0` → early return | — | n/a (idempotent guard; NOT a revert) |
| GameOver.handleGameOverDrain:94 | `preRefundAvailable != 0 && rngWordByDay[day] == 0` | `E()` | **PERMANENT-CANDIDATE (column-critical)** — game-over finalization reverts if funds exist but RNG word missing. Caller (`_handleGameOverPath`) is documented to guarantee the word is set before this call; if that guarantee is ever broken, gameOver finalization cannot complete. Defense-in-depth gate on the gameover path. |
| GameOver.handleGameOverDrain:130 | `claimablePool += uint128(totalRefunded)` cast truncation | silent cast (bounded) | TRANSIENT |
| GameOver.handleGameOverDrain:177 | nested `runTerminalDecimatorJackpot` self-call reverts | bubbles via Game stub `_revertDelegate` | **PERMANENT-CANDIDATE (column-critical)** — if the terminal decimator resolution reverts, the whole `handleGameOverDrain` tx reverts and game-over cannot finalize (gameOver=true rolls back). The decimator resolve has only the OnlyGame gate (satisfied) + a uint256 loop with no revert sites, so this is low-likelihood but in the column. |
| GameOver.handleGameOverDrain:180 | `claimablePool += uint128(decSpend)` cast | silent cast | TRANSIENT |
| GameOver.handleGameOverDrain:191 | nested `runTerminalJackpot` self-call reverts (JackpotModule, out of slice) | bubbles | **PERMANENT-CANDIDATE (column-critical)** — same wedge shape; resolution is in the Jackpot slice. |
| GameOver._creditClaimable / _setNextPrizePool / etc. | (no reverts; pure SSTORE/cast) | — | n/a |
| GameOver.handleFinalSweep:204-207 | not-over / too-early / already-swept → early return | — | n/a (idempotent guards, NOT reverts) |
| GameOver.handleFinalSweep:214-216 | `_debitClaimable` reverts if `uint128(balancesPacked[sink]) < owed` | `E()` | PERMANENT-CANDIDATE (column-adjacent, post-gameover) — owed is read via `_claimableOf` immediately prior, so debit cannot exceed it; effectively unreachable. If it ever fired, the final sweep (last chance for sinks) would be wedged. |
| GameOver._sendStethFirst:253/257 | `steth.transfer(...) == false` | `E()` | **PERMANENT-CANDIDATE** — hard-revert policy. A failing stETH transfer to VAULT/SDGNRS/GNRUS reverts the entire `handleFinalSweep`, blocking the 30-day sweep until the transfer succeeds. Documented as a deliberate hard-revert (lines 243-245). |
| GameOver._sendStethFirst:261 | `payable(to).call{value:ethAmount}("") == false` (ETH send rejected by sink) | `E()` | **PERMANENT-CANDIDATE** — a sink contract that reverts on ETH receipt wedges `handleFinalSweep`. Sinks are VAULT/SDGNRS/GNRUS (protocol contracts); the bubble bricks the final sweep until they accept ETH. |
| GameOver.handleGameOverDrain:139-142 | `charityGameOver.burnAtGameOver()` / `dgnrs.burnAtGameOver()` / `flip.tombstoneAtGameOver()` revert | bubbles (no try/catch) | **PERMANENT-CANDIDATE (column-critical)** — these 3 synchronous external calls have NO try/catch; if any reverts, `handleGameOverDrain` reverts and game-over cannot finalize. See callee-revert section. |
| GameOver.handleFinalSweep:220 | `admin.shutdownVrf()` revert | swallowed by `try/catch` | TRANSIENT (fire-and-forget; failure does NOT block sweep) |

---

## 3. LOOP INVENTORY

| fn:line | iteration-count bound | per-iteration storage/gas | classification |
|---|---|---|---|
| DecModule.runDecimatorJackpot:243 `for denom 2..12` | FIXED 11 iterations (denom 2→12) | reads `decBucketBurnTotal[lvl][denom][winningSub]` (1 SLOAD), pure pack | BOUNDED (constant 11) |
| DecModule.runTerminalDecimatorJackpot:995 `for denom 2..12` | FIXED 11 iterations | `keccak256` + `terminalDecBucketBurnTotal[bucketKey]` (1 SLOAD) | BOUNDED (constant 11) |
| DecModule.claimDecimatorJackpotMany:343 `for i < players.length` | **INPUT-SIZED** = `players.length` (caller-supplied array) | per claimant: `_decClaimableFromEntry` (SLOADs), `_claimDecimatorJackpotFor` (writes `e.claimed`, `_creditClaimable`, possibly `claimablePool -=`, lootbox nested delegatecall, `_setFuturePrizePool`), settle counter | **UNBOUNDED / INPUT-SIZED** — caller controls length; off-column (permissionless side path), so a too-large array reverts only the caller's own tx. Not in advanceGame chain. |
| GameOver.handleGameOverDrain:106 `for i < ownerCount` (deity refund) | `deityPassOwners.length` (only when `lvl < 10`) | per owner: `deityPassOwners[i]` SLOAD, `deityPassPricePaid[owner]` SLOAD, `_creditClaimable` (SSTORE + event) | **STATE-SIZED (deity owners), column-relevant** — runs INSIDE `handleGameOverDrain` (the game-over finalization). Bounded only by the number of deity passes sold at levels 0-9. Deity passes are 1-per-symbol (≤32 symbols), so practically ≤32, but the loop has no explicit cap — sized by `deityPassOwners.length`. `break` once budget exhausts. Brick-relevant IF deity-owner count could be large; design caps deity slots. |

---

## 4. DELEGATECALL STORAGE-WRITE INVENTORY (Game slots written by this slice)

All writes below land in DegenerusGame storage (module runs via delegatecall).

### PayoutUtils
- `_creditBoxProceeds`: `claimablePool` (+= boxEth); `balancesPacked[VAULT]` and `balancesPacked[SDGNRS]` via `_creditClaimable` (low-128 claimable half). [packed slot: balancesPacked claimable/afking halves]
- `_queueWhalePassClaimCore`: `whalePassClaims[winner]` (+=); `balancesPacked[winner]` (claimable half) via `_creditClaimable`.

### Decimator — regular
- `recordDecBurn`: `decBurn[lvl][player]` struct fields — `.bucket` (453,824 style writes @159/168/169), `.subBucket` (@160/167/169), `.burn` (@190). **PACKED-SLOT, keyed by (lvl, player); offset-keyed by `bucket`/`subBucket` packed into the DecEntry word.** Also `decBucketBurnTotal[lvl][denom][sub]` via `_decUpdateSubbucket` (@601 +=) and `_decRemoveSubbucket` (@619 -=). **All keyed by lvl + denom + sub.**
- `runDecimatorJackpot`: `decBucketOffsetPacked[lvl]` (@269) — **PACKED uint64, keyed by lvl, 4 bits/denom** (the regular-round winning-subbucket map; the DEC-ALIAS sibling of the terminal `[lvl+1]` write). `decClaimRounds[lvl]` struct: `.poolWei` (@273), `.totalBurn` (@274), `.rngWord` (@277) — **packed single slot keyed by lvl.**
- `_claimDecimatorJackpotFor`: `decBurn[lvl][player].claimed` (@399 =1); `balancesPacked[player]` claimable half via `_creditClaimable`; on lootbox branch `claimablePool` (-= via `_creditDecJackpotClaimCore`), `prizePoolsPacked` future half via `_setFuturePrizePool`/`_getFuturePrizePool` (@414). **prizePoolsPacked is PACKED (next | future<<128).**
- `_creditDecJackpotClaimCore`: `balancesPacked[account]` (claimable, `_creditClaimable`); `claimablePool` (-= @462).
- `_awardDecimatorLootbox`: `mintPacked_[winner]` via `_applyWhalePassStats` (PACKED bit-fields: LEVEL_COUNT, FROZEN_UNTIL_LEVEL, WHALE_BUNDLE_TYPE, LAST_LEVEL, DAY, mint-streak); `ticketQueue[wk]`, `ticketsOwedPacked[wk][buyer]` (PACKED owed<<8|rem) via `_queueTicketRange`. Then NESTED delegatecall to LOOTBOX_MODULE writes its own slots (out of this slice's enumeration).
- `claimDecimatorJackpotMany`: same writes as `_claimDecimatorJackpotFor` per claimant; plus the keeper bounty is an EXTERNAL `coinflip.creditFlip` (NOT a Game-storage write).

### Decimator — terminal
- `recordTerminalDecBurn`: `terminalDecEntries[player]` struct — full-slot reset write (@808 packed struct) when stale; `.bucket` (@824), `.subBucket` (@825), `.totalBurn` (@841, uint80, clamp), `.weightedBurn` (@851, uint88, clamp), `.burnLevel` (set in reset). **PACKED single 240/256-bit slot keyed by player; fields offset within the word.** Also `terminalDecBucketBurnTotal[keccak(lvl,bucket,sub)]` (@855 +=) — **keyed by (lvl,bucket,sub) hash.**
- `boostTerminalDecimator`: `terminalDecEntries[player].bucket` (@927), `.subBucket` (@928), `.weightedBurn` (@931, uint88), `.boosted` (@932 =true). **Same PACKED player slot.** `terminalDecBucketBurnTotal[oldKey]` (-= @942 on promotion; += @945 non-promotion), `terminalDecBucketBurnTotal[newKey]` (+= @943 on promotion) — **re-key conserving total weight.**
- `runTerminalDecimatorJackpot`: `decBucketOffsetPacked[lvl + 1]` (@1024) — **PACKED uint64 keyed by lvl+1 (DEC-ALIAS isolation: deliberately NOT lvl, to avoid aliasing the live regular round's `decBucketOffsetPacked[lvl]`).** `lastTerminalDecClaimRound`: `.lvl` (@1027), `.poolWei` (@1028), `.totalBurn` (@1029) — **packed single slot (248/256 bits).**
- `claimTerminalDecimatorJackpot` → `_consumeTerminalDecClaim`: `terminalDecEntries[player].weightedBurn` (@1113 =0, claimed flag). `balancesPacked[msg.sender]` claimable half via `_creditClaimable`.

### GameOver
- `handleGameOverDrain`: `gameOverStatePacked` via `_goWrite` — **PACKED: GO_TIME (bits 0:47, @136), GO_JACKPOT_PAID (bits 48:55, @144).** `gameOver` bool (@135 =true). `balancesPacked[owner]` claimable half (deity refund loop, `_creditClaimable` @117). `claimablePool` (+= @130 deity, += @180 decSpend). `prizePoolsPacked` — `_setNextPrizePool(0)` @145, `_setFuturePrizePool(0)` @146 (both write the PACKED next|future slot); `currentPrizePool` via `_setCurrentPrizePool(0)` @147. `yieldAccumulator` (=0 @148). Plus the nested self-calls (`runTerminalDecimatorJackpot`, `runTerminalJackpot`) write decimator/jackpot slots.
- `handleFinalSweep`: `gameOverStatePacked` via `_goWrite(GO_SWEPT...)` (@209 =1) — **PACKED GO_SWEPT bits 56:63.** `balancesPacked[VAULT/SDGNRS/GNRUS]` claimable half via `_debitClaimable` (@214-216). `claimablePool` (=0 @217).

PACKED-SLOT HOTSPOTS (aliasing-relevant, keyed by offset/level/day):
- `decBucketOffsetPacked[lvl]` (regular, runDecimatorJackpot:269) vs `decBucketOffsetPacked[lvl+1]` (terminal, runTerminalDecimatorJackpot:1024) — the DEC-ALIAS pair; terminal deliberately offset to +1 so a gameover at `lvl` cannot corrupt a live regular round at `lvl`.
- `gameOverStatePacked` written at three offsets: GO_TIME@136, GO_JACKPOT_PAID@144 (handleGameOverDrain) and GO_SWEPT@209 (handleFinalSweep) — same slot, distinct shifts.
- `prizePoolsPacked` (next|future<<128) written by `_setNextPrizePool`/`_setFuturePrizePool` in both decimator claim and gameover drain.
- `balancesPacked[player]` (claimable low 128 | afking high 128) credited/debited across all claim + gameover paths.
- `decBurn[lvl][player]` DecEntry (burn/bucket/subBucket/claimed in one word); `terminalDecEntries[player]` (totalBurn/weightedBurn/bucket/subBucket/burnLevel/boosted in one word).
- `ticketsOwedPacked[wk][buyer]` (owed<<8|rem) + `mintPacked_[winner]` bit-fields, written via `_awardDecimatorLootbox` → `_queueTicketRange`/`_applyWhalePassStats`.
