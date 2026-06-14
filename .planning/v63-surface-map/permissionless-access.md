# v63 Change-Surface Map — Dimension: New permissionless entrypoints, access control & reentrancy

BASELINE 77580320 → SUBJECT a8b702a7 (~60 commits: gas rounds 3-8, storage-packing A/B, BURNIE
emission rework, EVM-target bumps, several gameplay/economic features). READ-ONLY analysis.

This dimension catalogs the new/widened permissionless surface and adjudicates, for each new or
changed external entrypoint: caller authorization, keeper-bounty economics vs. REAL prevailing gas
(not the 0.5-gwei peg) and flip-credit illiquidity, ETH/stETH reentrancy, and whether a permissionless
caller can grief liveness or steer an RNG outcome by choosing when/what to call.

The big architectural change underneath everything: `DegenerusGame.sol` became a thin selector-matched
delegatecall dispatcher. Every external function is an explicit stub of the form
`(...).delegatecall(msg.data)` into the owning module (verified: each new entrypoint has its own stub,
e.g. `claimDecimatorJackpot(address,uint24)` at DegenerusGame.sol:808, `claimDecimatorJackpotMany` at
:832). Delegatecall preserves `msg.sender` and `address(this)`, so module-side `msg.sender` is the
external caller and module-side external calls (e.g. `coinflip.creditFlip`) originate from the GAME
address. This means module-side access gates (`msg.sender != COIN`, etc.) and the
`onlyFlipCreditors`/`onlyGame` checks on callees remain correct under the dispatcher. No stub
mis-routes a permissionless entrypoint into a gated one or vice versa.

---

## 1. Permissionless decimator claims (DegenerusGameDecimatorModule.sol)

### What changed
- The self-only `claimDecimatorJackpot(uint24 lvl)` (caller == winner) was REPLACED with a fully
  permissionless `claimDecimatorJackpot(address player, uint24 lvl)` (module :293). Anyone may
  resolve any winner's claim; all value credits to `player`, never the caller.
- New `claimDecimatorJackpotMany(address[] players, uint24 lvl)` (module :325) batch-resolves a list,
  skipping already-claimed / non-winner entries (no revert-on-stale), with a keeper bounty.
- The old GAME-only `consumeDecClaim` was removed; `_consumeDecClaim` folded into a shared
  `_claimDecimatorJackpotFor` core (:385) used by both new entry points.
- Keeper bounty: `BOX_BOUNTY_ETH_TARGET = 15_000_000_000_000` wei (0.000015 ETH) per settled box,
  paid only `!gameOver && settled != 0`, as `(settled * TARGET * PRICE_COIN_UNIT) / _mintPriceInContext()`
  BURNIE flip-credit to `msg.sender` (:364-370).
- Terminal-decimator offset DEC-ALIAS fix: terminal winners are now keyed at
  `decBucketOffsetPacked[lvl + 1]` (module :1014-1037, :1063, :1095) so a gameover-at-lvl terminal
  round can't overwrite a still-live regular round keyed at `lvl`.

### Authorization
Correct. `claimDecimatorJackpot`/`Many` credit only `player` (the winner). No ETH leaves these
functions — they resolve into `claimablePool`/`futurePrizePool` and the winner withdraws via the
access-gated `claimWinnings`. Both gate on `prizePoolFrozen` (revert during the VRF freeze window) so
they can't corrupt the live pool advanceGame operates on.

### Bounty economics vs. real gas (faucet test)
Per box the bounty is 0.000015 ETH of value, delivered as ILLIQUID coinflip flip-credit
(`creditFlip` → `_addDailyFlip`, i.e. next-day stake that must survive a 50/50 flip to mint).
At the 0.5-gwei peg that equals ~30k gas (the claimed per-box settle cost). At REAL prevailing gas
the per-box settle (~30k gas + the lootbox-resolve delegatecall it does for a live winner) costs far
more: at 20 gwei a single box-settle tx is ~0.0006+ ETH while the reward is 0.000015 ETH — ~40x
under-water BEFORE the 50% flip risk and illiquidity. Critically, every claimable box exists only
because a real player BURNED decimator BURNIE (the regression asserts `bounty << 500 BURNIE` burn
cost). So a Sybil cannot manufacture boxes to farm the bounty; settling others' boxes is liveness
work that roughly breaks even at the peg and is net-negative at any realistic price.
DecimatorBountyRegression.t.sol pins all five rules (per-box, scales, no-pay-post-gameover, ETH-value
holds across the price curve, faucet << burn cost). `_mintPriceInContext()` (:376) reproduces the
Game's `mintPrice()` (`priceForLevel(jackpotPhaseFlag ? level : level+1)`) exactly, so the bounty
size can't be skewed by the caller and the ETH-value is price-independent.

### RNG / outcome-steering
The lootbox seed for a live-game decimator claim is the FROZEN `round.rngWord` snapshotted in
`runDecimatorJackpot` (:277, narrowed to uint32 at packing — winners were already selected from the
full word). `_creditDecJackpotClaimCore` → `_awardDecimatorLootbox` derives the box seed from that
frozen word + player + amount, and the EV multiplier from `_minScoreForBucket(winBucket, lvl)` where
`winBucket` is the bucket SEALED at burn time. So the claimer cannot re-roll the win/loss or the EV
multiplier by being a third party or by timing. This is the established by-design lootbox-timing
posture (memory: lootbox-resolution-timing-by-design).

### Residual lead (timing forced on the winner)
NEW capability: a third party can now FORCE a winner's live-game decimator claim to resolve at a
`level` the winner did not choose. The lootbox `_rollTargetLevel(level+1, frozenSeed)` and the
whale-pass `_queueTicketRange(winner, level+1, ...)` read the LIVE `level` at claim time. A griefer
could settle a winner's box at an adverse live level (e.g. just before an advance that would shift the
target-level distribution, or that would change the whale-pass start level). The frozen seed prevents
win/loss steering, but the LEVEL the reward lands at is now externally controllable. Memory rules this
class by-design (permissionless economically-incentivized resolution; timing not a player edge), and
the design comment states removing exclusive claim timing is intentional — but this is a genuine new
externally-forceable timing surface worth a closer adversarial look (does any reward magnitude /
target-level distribution actually diverge enough between adjacent levels to make forced resolution
materially harmful to the winner?). Severity LOW.

### Batch gas-grief
`claimDecimatorJackpotMany` loops `players.length` unbounded, but the caller pays their own gas, the
loop skips non-winners, and it is NOT in the advanceGame chain — no protocol liveness impact. Self-
limiting.

---

## 2. Live-game permissionless redemption claims (StakedDegenerusStonk.sol)

### What changed
- `claimRedemption(address player, uint24 day)` (sDGNRS :771) — permissionless during a LIVE game
  (anyone settles any `player`); SELF-CLAIM-ONLY post-gameOver (`isGameOver && player != msg.sender`
  reverts Unauthorized).
- New `claimRedemptionMany(address[] players, uint24 day)` (:787) batch-settles, skipping empty slots
  and (post-gameOver) all non-self entries, with a keeper bounty mirroring the decimator one
  (`BOX_BOUNTY_ETH_TARGET`, paid `!isGameOver && settled != 0`, as `creditFlip(msg.sender, ...)`).
- Dust-lootbox drop (commit 78b858ed): when the 50% lootbox half lands below
  `MIN_REDEMPTION_LOOTBOX_ETH` (0.01 ETH) it is FORFEITED to sDGNRS's own claimable (raising backing),
  not paid to the player (:839-848, :897-901).
- The removed `claimCoinflipsForRedemption` (coinflip) + the tightened coinflip `onlyBurnieCoin`
  modifier (dropped SDGNRS) — the redemption BURNIE leg now settles entirely at submit via
  `redeemBurnieShare` (atomic burn+consume+creditFlip, net-zero new BURNIE).
- The payable delegatecall chain fix (403afc62) so the ETH leg of a live claim reaches
  `resolveRedemptionLootbox`/`creditRedemptionDirect` with `msg.value` intact.

### Authorization
Correct. Live claims credit only `player`: both legs forward into the Game (50% to the player's game
claimable via `creditRedemptionDirect`, 50% to the lootbox via `resolveRedemptionLootbox`), so a
third-party trigger pushes no ETH at the player and holds no exclusive timing. Post-gameover is
self-claim only (avoids a third party forcing a game-claimable credit that the post-gameover sweep
would forfeit). The Game-side callees `resolveRedemptionLootbox` (:926) and `creditRedemptionDirect`
(:1004) both gate `msg.sender != SDGNRS`.

### Bounty economics
Identical shape and constant to the decimator bounty — same -EV-at-real-gas + illiquid-credit
analysis. Every settled box exists only because a holder gambling-burned sDGNRS, so it can't be
manufactured to farm. sDGNRS is an authorized `onlyFlipCreditors` caller, so the credit lands AS
sDGNRS.

### RNG / outcome-steering
The redemption lootbox seed `EntropyLib.hash2(rngWord, player)` with `rngWord = game.rngWordForDay(day
+ 1)` (:878). The roll `redemptionPeriods[day]` is fixed at resolution. The seed mixes `player`, NOT
`msg.sender`, so a keeper can't steer by choosing themselves. The day+1 word is the future word
unknown at SUBMIT time — the submit-side gate `_submitGamblingClaimFrom` requires
`game.rngWordForDay(currentPeriod) != 0` (BurnsBlockedBeforeDailyRng, :991) which pins the burn to a
drawn day so the pool always resolves on the NEXT day's draw, and the burn()/burnWrapped() entry gates
on `rngLocked`/`livenessTriggered`. By claim time the period is resolved, so day+1's word is set. The
freshness invariant (word unknown at input-commitment) holds; the d8778c3e/832c8eb3 redemption
pre-draw gate is intact.

### Reentrancy across ETH/stETH legs
- Post-gameover `claimRedemption` deletes the `pendingRedemptions[player][day]` slot and lowers
  `_pendingRedemptionEthValue` BEFORE the untrusted `_payEth` (.call) — CEI. `_payEth` (:1098) sends
  stETH first, then the ETH .call last.
- Live legs send ETH+stETH to the Game (`resolveRedemptionLootbox`/`creditRedemptionDirect`); the slot
  is already deleted and `_pendingRedemptionEthValue` already lowered before those calls. The Game-side
  handlers pull the stETH remainder via `steth.transferFrom` (sDGNRS pre-approves GAME max) and credit
  pools — no ETH pushed at the player from these legs.
- The Game's own claim payout `_payoutWithStethFallback` (DegenerusGame.sol:1888) was reordered
  (53cd25cf) to move the stETH leg out FIRST and run the untrusted ETH .call LAST, closing the
  council/V62-03 solvency-reentrancy (a reentrant `distributeYieldSurplus` reading in-flight stETH as
  unreserved backing). `distributeYieldSurplus` is reachable only internally from advanceGame
  (`_distributeYieldSurplus`, AdvanceModule:529/783) — no external Game stub — and only CREDITS
  claimable (no ETH out), and only when `totalBal > obligations`, so it is not an independently
  exploitable permissionless lever.

### Residual leads
- (a) Forfeit-to-self leg: dust lootbox forfeits to `sDGNRS`'s own claimable. A keeper choosing WHICH
  redemptions to settle could, in aggregate, bias when forfeits land vs. when full lootboxes resolve,
  but the per-claim split is deterministic from the fixed roll + the player's own owed value, so there
  is no per-victim value extraction — only a benign timing of backing accrual. Severity INFO.
- (b) Balance-clamp legs: each leg sends `min(address(this).balance, legAmount)` ETH and pulls the
  rest as stETH. The comment asserts the MAX (175%) reservation guarantees ETH+stETH >= rolled. Worth
  confirming under an adversarial sequence of many partial-balance live claims in one block that the
  segregation accounting (`_pendingRedemptionEthValue` release == total leg movement) can never strand
  ETH or under-pull stETH. Severity LOW (accounting-precision lead, not an obvious break).

---

## 3. New `claimCoinflipCarry(address player, uint256 amount)` (BurnieCoinflip.sol:366)

### What changed
New entry point letting a player (or operator-approved caller via `_resolvePlayer`) withdraw up to
`amount` of the auto-rebuy carry as minted BURNIE while staying on auto-rebuy.

### Authorization
`player = _resolvePlayer(player)` (self or operator-approved), mints to `player` not caller. Correct.

### RNG window
Gated by `if (degenerusGame.rngLocked()) revert RngLocked()` (:371), same gate as the rebuy toggle.
It first settles all RESOLVED days (`_claimCoinflipsInternal(player, false)` — only days with a
recorded result, bounded by the claim window), rolling wins into the carry and zeroing it on a pending
loss, THEN pays out of the SETTLED carry. Because the day's word may be on-chain before the resolution
walk applies it, the RNG-lock gate prevents minting a carry that should still be at flip risk. It
cannot mint unsettled (pending-day) stake. Sound, consistent with the existing rebuy-toggle freeze.

---

## 4. Widened coinflip claim windows + emission rework (BurnieCoinflip.sol)

### What changed
- `COIN_CLAIM_DAYS` 90 → 365, `AUTO_REBUY_OFF_CLAIM_DAYS_MAX` 1095 → 1460 (window-day loop caps).
- Day-result and stake storage repacked (32 days/slot 3-state byte; 2 days/slot 128-bit wei lanes) —
  lossless, no semantic change to claim logic.
- BURNIE emission seed (b11fd610): a `constructor()` seeds 200k BURNIE/day for days 1-20 as flip
  stakes to VAULT and SDGNRS; `processCoinflipPayouts` arms sDGNRS perpetual auto-rebuy once the final
  seeded day settles (`sdgnrsAutoRebuyArmed` one-shot latch, :846-454).
- `onlyBurnieCoin` tightened to COIN only (SDGNRS dropped); `onlyFlipCreditors` unchanged set
  {GAME, QUESTS, AFFILIATE, ADMIN, SDGNRS}.

### Liveness / gas
The widened caps lengthen the worst-case per-player CLAIM loop, but claims are user-paid and out of
the advanceGame chain. The advanceGame-chain sDGNRS auto-settle in `processCoinflipPayouts`
(`onlyDegenerusGameContract`, once/day) walks only the days since sDGNRS's last claim — `deep` is
false in both the armed (`_claimCoinflipsInternal(SDGNRS, false)`) and pre-arm
(`_claimCoinflipsAmount(SDGNRS, max, true)` with rebuy disabled ⇒ deep=false) branches, so it is
bounded by `windowDays` (365) and in steady state processes ~1 day/advance. The 1460-day deep cap +
365-day window perma-brick gas was pinned by a dedicated regression (0a2209d4). No new advanceGame
brick risk identified, but the 365/1460 worst-case loops merit a fresh gas check under the new packed
storage layout (each day is now a masked sub-word read/write).

### Authorization
The dropped SDGNRS from `onlyBurnieCoin` is correct (the SDGNRS redemption-consume path moved to
submit-time `redeemBurnieShare`, which is SDGNRS-gated). No widening.

---

## 5. Other access-surface deltas (incidental / verified non-widening)

- DegenerusGame.sol thin-dispatcher refactor: signature-identical stubs, no access change.
- JackpotModule: `distributeYieldSurplus(uint256)` and `payDailyCoinJackpot` retain access (only
  internal/onlyGame reach); the diff is gas/caching + jackpot-execution restructuring, not new surface.
- WhaleModule: internal refactors only — no new external entrypoints, no access change.
- `depositCoinflip` / `setCoinflipAutoRebuy` / `claimCoinflips` all routed through the unified
  `_resolvePlayer` helper (replacing the prior inline self/operator-approval logic) — behavior-
  preserving; the `fromGame` short-circuit in `setCoinflipAutoRebuy` (:660-666) preserves the GAME
  caller path.
- `claimWinnings` uses `_resolvePlayer` + credits `player`; `claimWinningsStethFirst` is VAULT-gated.

---

## Net assessment for this dimension

Three genuinely-new permissionless entrypoints (`claimDecimatorJackpot(address,uint24)`,
`claimDecimatorJackpotMany`, `claimRedemptionMany`) plus the new `claimCoinflipCarry`. All credit the
beneficiary not the caller, all gate the freeze/rng/liveness windows correctly, all use FROZEN RNG
seeds that mix `player` (not `msg.sender`) so no third party can steer win/loss or EV. Both keeper
bounties are illiquid flip-credit, far below real gas at any realistic price, and structurally
un-manufacturable (each box costs a real burn). Reentrancy across the ETH/stETH legs follows CEI
(slot delete + ledger debit before untrusted .call; stETH-first/ETH-last; the council solvency fix is
in place). The principal NEW adversarial lead is FORCED claim timing: a third party can now make a
winner's live-game decimator (and, more weakly, redemption) reward LAND at a level/time the winner
didn't pick — frozen seeds bound the randomness, but the live-level-dependent target-level roll and
whale-pass start level are externally forceable. Memory rules this by-design, so it is a verify-the-
magnitude lead, not a presumed finding. Secondary leads: the redemption partial-balance leg
accounting under many same-block claims, and a fresh gas pass on the widened 365/1460 claim loops over
the new packed storage.
