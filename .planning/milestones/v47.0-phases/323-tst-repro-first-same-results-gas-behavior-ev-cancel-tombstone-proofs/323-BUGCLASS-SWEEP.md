# 323 BUGCLASS SWEEP — Post-Game-Over Unbacked-Credit Siblings

**Date:** 2026-05-25
**Subject commit (contracts/):** `fabe9e94` (git HEAD)
**v46 baseline ref:** `16e9668a`
**Mode:** READ-ONLY analysis. No contract edits. No `CONTRACTS_COMMIT_APPROVED`.
**Seed finding (fixed, excluded):** `DegeneretteModule.resolveBets` insolvency — now guarded at
`DegenerusGameDegeneretteModule.sol:421` (`if (_livenessTriggered()) revert E();`).

---

## Bug-class signature (recap)

An entrypoint **reachable after `_livenessTriggered()` is true** that **credits an ETH obligation**
(`claimableWinnings[x] +=`, `claimablePool +=`, `_creditClaimable`, `_addClaimableEth`,
`_creditBoxProceeds`, `_queueWhalePassClaimCore`) from a value source the game-over drain already
distributed (the prize pools), **without bringing in matching real ETH this tx**.

Discriminator:
- A credit decoupled from `advanceGame` and independently/permissionlessly callable post-game-over → **suspect.**
- `advanceGame`-driven credits are **SAFE**: `advanceGame` returns at `_handleGameOverPath`
  (`DegenerusGameAdvanceModule.sol:182` → return at :195) before any daily/level-transition credit runs.
- Real-ETH-in credits (msg.value-funded) are **SAFE** (backed).
- Credits drawn from a `claimablePool` reservation that the drain **respects** (subtracts as `reserved`,
  does not redistribute) are **SAFE** (the backing ETH stayed in the contract).

---

## Drain mechanics (the thing siblings would race)

`handleGameOverDrain` (`DegenerusGameGameOverModule.sol:78`) — reached ONLY via
`advanceGame → _handleGameOverPath` (`DegenerusGameAdvanceModule.sol:614`); idempotent (latched by
`GO_JACKPOT_PAID` at :79). It:
1. Reads `reserved = claimablePool` (:90) and distributes only `totalFunds − reserved` (:91/:154) —
   **so any pre-existing `claimablePool` reservation is preserved, not redistributed.**
2. Zeroes `nextPrizePool / futurePrizePool / currentPrizePool / yieldAccumulator` (:145–148) —
   these pools become value sources an unguarded post-drain credit could double-spend.
3. Credits deity-pass refunds + terminal decimator/jackpot, each matched by a `claimablePool +=`
   (:132/:169) so `claimablePool == Σ claimableWinnings` holds.

`handleFinalSweep` (:192) — also reached only via `advanceGame`; pays the three sinks then zeroes
`claimablePool`. After `GO_SWEPT`, `claimWinnings()` reverts.

**Key accounting fact:** `_creditClaimable` (`DegenerusGamePayoutUtils.sol:22`) bumps ONLY
`claimableWinnings[x]`, never `claimablePool`. The pool-side reservation is always done by the caller
(or pre-reserved upstream). This is exactly why the Degenerette path was unbacked: it credited
`claimableWinnings` from drained `futurePool` residual with no live pool to back it.

---

## Verdict table — every ETH-obligation credit site

| # | Site | Enclosing fn | External entrypoint(s) | Post-GO reachable? | Backed / Unbacked | Verdict |
|---|------|--------------|------------------------|--------------------|-------------------|---------|
| 1 | DegeneretteModule:436/1190-1191 | resolveBets / _addClaimableEth | resolveDegeneretteBets (Game:778), _crankResolveBet (Game:1684, try/catch) | **NO** — guarded :421 | n/a | SAFE (FIXED seed) |
| 2 | GameOverModule:120,132 | handleGameOverDrain (deity refund) | advanceGame→_handleGameOverPath:614 | This IS the drain (once, latched :79) | Backed (part of drain) | SAFE |
| 3 | GameOverModule:169 | handleGameOverDrain (terminal dec reserve) | advanceGame→_handleGameOverPath:614 | This IS the drain | Backed (reserves decPool) | SAFE |
| 4 | JackpotModule:719-723 | distributeYieldSurplus | advanceGame→_distributeYieldSurplus:420 | NO (returns at :195) | n/a | SAFE |
| 5 | JackpotModule:1143 | _processDailyEth | payDailyJackpot (advanceGame:380/463) | NO | n/a | SAFE |
| 6 | JackpotModule:1275 | _resolveTraitWinners | payDailyJackpot* (advanceGame) | NO | n/a | SAFE |
| 7 | JackpotModule:1368 | _payNormalBucket | payDailyJackpot* (advanceGame) | NO | n/a | SAFE |
| 8 | JackpotModule:1407,1415 | _processSoloBucketWinner | payDailyJackpot* (advanceGame) | NO | n/a | SAFE |
| 9 | JackpotModule:1960,1989 | runBafJackpot | self-call only (:1935), from advanceGame:819 | NO | n/a | SAFE |
| 10 | JackpotModule:1978,2030 | runBafJackpot / _awardJackpotTickets | self-call, advanceGame BAF | NO | n/a | SAFE |
| 11 | JackpotModule:745 | _addClaimableEth (helper) | (callers above) | NO | n/a | SAFE |
| 12 | JackpotModule:384/408-409/473/532/643/688/774 | payDailyJackpot / _runEarlyBird / _distributeLootboxAndTickets (pool writes) | advanceGame daily | NO | n/a | SAFE |
| 13 | DecimatorModule:334 | claimDecimatorJackpot (gameOver branch) | claimDecimatorJackpot (Game:1287) — **permissionless, post-GO** | **YES** | **Backed** — pool reserved into claimablePool at resolution (AdvanceModule:843-845/894); drain subtracts it as `reserved` | SAFE |
| 14 | DecimatorModule:391,394 | _creditDecJackpotClaimCore (non-GO branch) | claimDecimatorJackpot — non-GO branch only | NO (gameOver branch returns at :336) | n/a (pre-GO) | SAFE |
| 15 | DecimatorModule:592 | _awardDecimatorLootbox (whale remainder) | claimDecimatorJackpot non-GO branch | NO (pre-GO only) | pre-GO; see OBS-1 | SAFE (out of class) |
| 16 | DecimatorModule:839 | claimTerminalDecimatorJackpot | claimTerminalDecimatorJackpot (Game:1303) — **permissionless, post-GO BY DESIGN** | **YES** | **Backed** — full `poolWei` reserved into claimablePool at drain (GameOverModule:169) before any claim | SAFE |
| 17 | MintModule:1294 | _buyPresaleBoxFor → _creditBoxProceeds | buyPresaleBox (:1219) / buyLootboxAndPresaleBox (:1233) | **NO** — guarded :1262 (+ presaleOver latch :1261) | n/a | SAFE |
| 18 | PayoutUtils:39-41,56-58 | _creditBoxProceeds / _queueWhalePassClaimCore | (callers #16/#17/#9/#10) | inherits caller gating | inherits | SAFE |
| 19 | AdvanceModule:894 | _settleRewardJackpots (claimableDelta) | advanceGame level-transition | NO | n/a | SAFE |
| 20 | Storage:762 | _swapAndFreeze (futurePool↔pending) | advanceGame freeze path | NO; also not an ETH-obligation credit | n/a | SAFE |
| — | Decrement sites (Game:981/1443/1894, Storage:839, Degenerette:585, Decimator:394) | consume/payout | claimWinnings / mint / pullRedemptionReserve / shortfall | reduce obligations | n/a | SAFE (not in class) |

LootboxModule: grep for `claimableWinnings | claimablePool | _creditClaimable | _addClaimableEth |
_creditBoxProceeds | .call{value | payable(` → **NONE FOUND.** Awards tickets/BURNIE only.
**Class-safe, confirmed.**

---

## Why the two permissionless post-game-over credit sites (#13, #16) are NOT siblings

These are the only credit entrypoints that ARE callable when `_livenessTriggered()`/`gameOver` is true —
the exact shape of the Degenerette bug. Both are backed because the pool was reserved into
`claimablePool` *before* the claim, and the drain preserves existing `claimablePool`:

**#16 Terminal decimator (`claimTerminalDecimatorJackpot`)** — designed to run post-game-over.
`runTerminalDecimatorJackpot` (Decimator:780) runs *inside* the drain (GameOverModule:166). With winners
it returns 0 → `decSpend = decPool` → `claimablePool += decPool` (GameOverModule:169). The pool is reserved
up-front; each later claim credits `claimableWinnings` (pro-rata, Σ ≤ poolWei) drawing down that reservation.
`claimablePool == Σ claimableWinnings` holds; balance ≥ claimablePool holds. Backed.

**#13 Regular decimator gameover branch (`claimDecimatorJackpot`, Decimator:333-336)** — a regular
decimator round resolved *pre*-game-over moves its FULL pool out of `futurePool` into `claimablePool`
unconditionally at resolution time (AdvanceModule:843-845 → :894). The drain reads `reserved = claimablePool`
and never redistributes it (GameOverModule:90/154), so the backing ETH stays in the contract. A post-game-over
claim then credits `claimableWinnings` (`_creditClaimable`, no pool bump) against the pre-reserved pool.
The gameover branch credits the *full* `amountWei` (vs. half-ETH/half-lootbox pre-GO) precisely because the
full pool is still reserved and lootbox conversion is meaningless after game-over. Backed.

A regular decimator round and game-over cannot co-occur in one `advanceGame` call: `_handleGameOverPath`
returns at :195 before the level-transition jackpots run, so there is no path where the same `futurePool`
ETH is both reserved-for-a-round AND swept by the drain.

---

## v47-vs-pre-existing classification

`git diff 16e9668a HEAD -- contracts/modules/DegenerusGameDecimatorModule.sol` over the claim/credit/
gameover/poolWei/terminal lines → **empty diff.** The decimator claim accounting (#13, #16) and the
GameOverModule `decSpend`/refund reservations (#2, #3) are **byte-identical to the v46 baseline** —
pre-existing and already safe-by-reservation, not v47 regressions. (The v47 surface — coin-presale boxes
#17/#18, Degenerette resolveBets batching #1, sDGNRS redemption — is all either liveness-guarded or
real-ETH-backed.)

---

## OBSERVATIONS (out of THIS class — logged, not siblings)

- **OBS-1 (pre-GO, not in class): DecimatorModule:394 vs :592 whale-remainder under-reservation.**
  In `_creditDecJackpotClaimCore`, `claimablePool -= lootboxPortion` (full :394), then
  `_awardDecimatorLootbox` re-credits the sub-2.25-ETH `remainder` via `_creditClaimable` (:592) WITHOUT
  re-adding to `claimablePool`. This could make `claimablePool < Σ claimableWinnings` by `remainder`
  (an *under*-reservation → the remainder may be un-payable), not an *unbacked over-credit*. It runs
  ONLY pre-game-over (gameover branch returns at :336), so it is **outside the post-game-over class** and
  not a sibling. Flagged for separate review of the regular-decimator claim accounting if desired.
  (Pre-existing: identical at v46 baseline.)

- **OBS-2 (already tracked): `pullRedemptionReserve` (Game:1888) unchecked `claimablePool -=` underflow.**
  This is the known sDGNRS-redemption finding (MEMORY: `sdgnrs-redemption-lootbox-claimable-underflow.md`),
  a decrement/consume path, design-LOCKED and folded into v47 as
  `.planning/PLAN-SDGNRS-REDEMPTION-ACCOUNTING.md`. Not a post-game-over unbacked credit; out of class.

---

## BUGCLASS SWEEP: 0 SIBLINGS FOUND

Every ETH-obligation credit site is one of:
(a) `advanceGame`-gated — returns at game-over (`_handleGameOverPath`:182→:195) before any credit;
(b) self-call-only terminal jackpot — reached solely from the drain;
(c) liveness-guarded purchase / presale-box / Degenerette path (the FIXED seed + WhaleModule + MintModule);
(d) decimator claim backed by a `claimablePool` reservation the drain preserves.

No entrypoint credits an ETH obligation from a drained pool residual without matching backing.
The Degenerette `resolveBets` insolvency has no structural siblings at HEAD.

No contract changes recommended. (OBS-1 surfaced for optional separate review of pre-GO regular-decimator
remainder reservation — present unchanged since v46, not an insolvency in the swept class.)
