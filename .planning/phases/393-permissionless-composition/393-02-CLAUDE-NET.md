# 393-02 — NET 2 (Claude adversarial net) — PERMISSIONLESS-COMPOSITION (ACCESS-01..05)

**Subject (byte-frozen):** `a8b702a7` (`git diff a8b702a7 -- contracts/` EMPTY before and after this
task). Every source line below was re-read via `git show a8b702a7:contracts/<File>.sol` — the working
tree was ignored. No `hardhat` was invoked; no contract source was touched.
**Net:** NET 2 = the deep Claude adversarial net, run INDEPENDENTLY (the authorization / bounty /
solvency / gate / reentrancy properties were attacked at the frozen source FIRST; the NET-1 council
leads — `393-01-COUNCIL-NET.md` + `council/access.gemini.txt` — are folded in at §7 at the END).
**Charge:** attempt to BREAK each property with a concrete reachable call sequence (multi-tx /
same-block burst / observe-then-retrigger where the ordering matters), record WHO gets the value, the
gate / CEI / reservation / un-manufacturability that settles it, and a provisional verdict
(CONFIRMED / REFUTED / BY-DESIGN / MONITOR).
**Threat weighting (AUDIT-V63-PLAN §4, USER-locked):** access-control / reentrancy / MEV =
LOW/confirmatory. The SUBSTANTIVE items in this slice are **ACCESS-02** (keeper box-bounty economics vs
REAL gas) and **ACCESS-04** (partial-balance burst solvency) — a real grief/faucet/steer or a
burst-solvency strand weighs higher, so those get dedicated rigorous treatment.

---

## 0. Cite reconciliation at the frozen source (the two NET-1 cite-drifts)

393-01 routed two gemini cite-drifts to reconcile here. Re-read at `a8b702a7`:

| Item | NET-1 (gemini) cite | Frozen-source TRUTH at `a8b702a7` | Note |
|------|---------------------|-----------------------------------|------|
| Decimator bounty constant | `15e12` wei (correct) | `BOX_BOUNTY_ETH_TARGET = 15_000_000_000_000` — **DegenerusGameDecimatorModule.sol:117** | gemini correct |
| Redemption bounty constant | `24e12` wei (~48k gas) | `BOX_BOUNTY_ETH_TARGET = 24_000_000_000_000` — **StakedDegenerusStonk.sol:348** | **gemini was RIGHT; the surface-map / plan-cite "both bounties 15e12 identical" was WRONG.** The two bounties are DISTINCT: decimator 15e12, redemption 24e12. The redemption settle is heavier (the stETH legs), so the larger target is the gas-reimbursement match. |
| `claimCoinflipCarry` entry | `BurnieCoinflip.sol:787` (mint) | entry **BurnieCoinflip.sol:754**; the `burnie.mintForGame(player, claimed)` mint line is **:777**; the `rngLocked` gate is **:759** | neither @366 nor :787 — the true entry is :754, mint :777 |

**Conclusion of the reconciliation:** the redemption bounty is 24e12, NOT 15e12. The net-negative
direction (ACCESS-02) is re-derived below at the TRUE constants — it holds at both (the redemption
24e12 reward against the ~48k-gas redemption settle is the SAME ~40x-under-water ratio at 20 gwei as the
decimator 15e12 against ~30k gas, because the bounty was sized to the per-box settle gas at the
0.5-gwei reference, so the ratio-to-real-gas is identical by construction). The carry verdict (ACCESS-01
beneficiary-only) rests on the corrected :754 entry / :759 rngLocked gate / :777 mint-to-player line.

---

## 1. The dispatcher fact (re-verified — underlies every entrypoint)

`contracts/DegenerusGame.sol` is a thin selector-matched delegatecall dispatcher. Each new entrypoint is
an explicit stub: `claimDecimatorJackpot(address,uint24)` @DegenerusGame.sol:1138,
`claimDecimatorJackpotMany` @:1150, the redemption callee stubs `resolveRedemptionLootbox`/
`creditRedemptionDirect` @:1525/:1545. `delegatecall` preserves `msg.sender` + `address(this)`, so
module-side `msg.sender` IS the external caller and module-side external calls (e.g. `coinflip.creditFlip`,
`steth.transferFrom`) originate from the GAME address. The callee gates (`msg.sender != SDGNRS` on
`resolveRedemptionLootbox` @LootboxModule:927 / `creditRedemptionDirect` @:1005; `onlyFlipCreditors` on
`coinflip.creditFlip`) therefore remain correct under the dispatcher. **Attack: a stub that mis-routes a
permissionless entrypoint into a gated callee, or strips a gate.** RESULT: no stub mis-routes — each new
permissionless stub delegatecalls its OWN module function whose gates are intact; the SDGNRS-gated
callees are reached only from sDGNRS (which holds the GAME-address identity via delegatecall from the
sDGNRS contract's own `game.resolveRedemptionLootbox{value}` call). REFUTED (no mis-route).

---

## 2. ACCESS-01 — beneficiary-only credit (every permissionless / widened entrypoint)

**PROPERTY:** every permissionless / widened claim forwards value to `player` (or into the player's
game-claimable / lootbox / minted BURNIE to player), never to `msg.sender`; a third-party trigger pushes
NO ETH at a victim and holds no exclusive timing edge; no path lets a third party force a credit a later
sweep forfeits.

**Attack tried:** for EACH entrypoint, trace WHO receives the value; look for a forced ETH push at a
victim, a route to the caller, or a third-party-forced credit a sweep forfeits.

| Entrypoint (`a8b702a7`) | WHO gets the value | Settling cite |
|-------------------------|--------------------|---------------|
| `claimDecimatorJackpot(address player, uint24 lvl)` @DecimatorModule:293 | `player` only — `_claimDecimatorJackpotFor(player,…)` (:316) credits `player`'s claimable (`_creditClaimable(account=player,…)` :459) + awards the lootbox to `winner=player` (:645-658). No ETH leaves the function (resolution into `claimablePool`/`futurePrizePool`; `player` withdraws via the access-gated `claimWinnings`). | DecimatorModule:293/:316/:385-422/:459 |
| `claimDecimatorJackpotMany(address[] players, uint24 lvl)` @DecimatorModule:325 | each `players[i]` only (same core :353); skips already-claimed / non-winner (no revert :353-356); the keeper bounty is a SEPARATE BURNIE flip-credit to `msg.sender` (§3) — never the players' jackpot ETH. | DecimatorModule:325/:353/:364-370 |
| `claimRedemption(address player, uint24 day)` @sDGNRS:771 | LIVE: both halves route to the GAME for `player` — 50% direct via `creditRedemptionDirect{value}(player,…)` (:892), 50% lootbox via `resolveRedemptionLootbox{value}(player,…)` (:884); dust forfeits to sDGNRS's OWN claimable (:898) raising backing for all holders, NOT the caller. Post-gameOver: SELF-CLAIM-only — `isGameOver && player != msg.sender` reverts `Unauthorized` (:775), then 100% direct push to `player` via `_payEth(player,…)` (:830). | sDGNRS:771/:775/:884/:892/:898/:830 |
| `claimRedemptionMany(address[] players, uint24 day)` @sDGNRS:787 | each `players[i]` only (same core :796); post-gameOver SKIPS all non-self (`isGameOver && player != msg.sender continue` :793); bounty → `msg.sender` is SEPARATE BURNIE flip-credit (§3), never the players' ETH. | sDGNRS:787/:793/:796/:810-814 |
| `claimCoinflipCarry(address player, uint256 amount)` @BurnieCoinflip:754 | `player = _resolvePlayer(player)` (self or operator-approved, :758); mints to `player` via `burnie.mintForGame(player, claimed)` (:777). The caller can only be `player` itself or its approved operator (operator-approval IS the trust boundary, [[open-e-operator-approval-trust-boundary]]). | BurnieCoinflip:754/:758/:777 |

**Forced-credit-then-forfeit attack:** post-gameOver redemption is self-claim-only EXACTLY to prevent a
third party forcing a game-claimable credit the post-gameover sweep would forfeit (the `Unauthorized`
revert @sDGNRS:775 + the `continue` skip @:793). Live-game claims credit the player's claimable (not a
forced ETH push), and that claimable is withdrawn normally — no sweep forfeits it during the live game
(this is the FC-390-03 ACCESS half — the batch caches `over`/`frozen` ONCE so no claim splits across the
boundary). **No path pushes ETH at a victim, routes value to the caller, or forces a forfeitable credit.**

**Provisional verdict: REFUTED (beneficiary-only holds on every entrypoint).**

---

## 3. ACCESS-02 — keeper box-bounty: dedicated REAL economic treatment (the substantive faucet item)

**PROPERTY:** the keeper bounty is net-NEGATIVE vs REAL prevailing gas (5/20/50+ gwei, NOT the 0.5-gwei
`AUTO_GAS_PRICE_REF` peg) + the BURNIE flip-credit illiquidity, AND it is un-manufacturable (each
settle-able box exists only because a real player burned), so no Sybil faucet exists.

**The bounty mechanics at the frozen source (re-read):**
- Decimator: `(settled * BOX_BOUNTY_ETH_TARGET * PRICE_COIN_UNIT) / _mintPriceInContext()` BURNIE
  flip-credited to `msg.sender`, paid only `!over && settled != 0` — DecimatorModule:364-370;
  `BOX_BOUNTY_ETH_TARGET = 15e12` (:117); `_mintPriceInContext()` (:376) reproduces the Game's
  `mintPrice()` = `priceForLevel(jackpotPhaseFlag ? level : level+1)` exactly.
- Redemption: `(settled * BOX_BOUNTY_ETH_TARGET * PRICE_COIN_UNIT) / game.mintPrice()` BURNIE
  flip-credited to `msg.sender`, paid only `!isGameOver && settled != 0` — sDGNRS:810-814;
  `BOX_BOUNTY_ETH_TARGET = 24e12` (:348). `creditFlip` is `_addDailyFlip` — a NEXT-DAY stake that must
  survive a 50/50 flip to mint (BurnieCoinflip `creditFlip`).

**(i) Real-gas cost vs the bounty (NOT the 0.5-gwei peg):**

| Settle | gas (settle + the live-winner lootbox-resolve delegatecall) | reward (ETH-value) | 5 gwei | 20 gwei | 50 gwei |
|--------|-----|--------|--------|---------|---------|
| Decimator per box | ~30k | 15e12 wei = 0.000015 ETH | cost 0.00015 ETH = **10x** | cost 0.0006 ETH = **40x** | cost 0.0015 ETH = **100x** |
| Redemption per box | ~48k | 24e12 wei = 0.000024 ETH | cost 0.00024 ETH = **10x** | cost 0.00096 ETH = **40x** | cost 0.0024 ETH = **100x** |

The bounty was sized to the per-box settle gas at the 0.5-gwei reference (the design comment, decimator
:362, redemption :807). So the reward-to-real-gas RATIO is IDENTICAL for both bounties by construction —
the redemption 24e12 reward against ~48k gas matches the decimator 15e12 against ~30k gas. At ANY real
prevailing gas (5x to 100x the 0.5-gwei peg) the bare-gas settle is 10x-100x the reward. **The bounty is
net-negative vs real gas BEFORE the flip risk and illiquidity.**

**(ii) Flip-credit illiquidity (the reward is worth far less than its ETH-target):** the bounty is paid
as BURNIE flip-credit via `creditFlip` → `_addDailyFlip` (next-day stake). To realize it as liquid value
the keeper must (a) survive a 50/50 flip (×0.5), then (b) sell BURNIE at the peg discount (~0.59) ⇒
realized liquid value ≈ 0.5 × 0.59 ≈ **0.30 × the ETH-target**. So the effective realized reward is
~0.0000045 ETH (decimator) / ~0.0000072 ETH (redemption) — making the keeper **~130x-330x under-water**
at 20-50 gwei. (This is the same illiquid-flip-credit accounting the 392 ECON-04 money-pump REFUTAL used:
`creditFlip`→`_addDailyFlip` ×0.5 ×0.59 ≈ 0.30·V.)

**(iii) Un-manufacturability (no Sybil faucet):** every settle-able box exists ONLY because a real player
BURNED:
- Decimator: a box is settle-able only for a real decimator winner whose entry was sealed at burn time
  (`e.bucket` @DecimatorModule:397, `e.claimed=1` @:399 prevents re-settle); a non-winner / already-claimed
  earns NOTHING (`settled` counts only real settles, :353-356). A keeper cannot fabricate a winning entry.
- Redemption: a box is settle-able only for a real `pendingRedemptions[player][day]` slot created by a
  real `redeemBurnieShare` gambling-burn (sDGNRS:991 `BurnsBlockedBeforeDailyRng` gate; a ≥1-whole-token
  redemption floor); `claim.ethValueOwed == 0 → return false` (:823) so an empty slot earns nothing
  (`settled` skips it). A keeper cannot fabricate a pending redemption.

So a Sybil cannot manufacture bounty-eligible work; settling OTHERS' boxes is liveness work that is
net-negative at any realistic price. **The bounty is a gas-reimbursement-shaped liveness incentive, not a
faucet.**

**Couple to FC-390-06 (issuance bound — REFUTED at 390):** the downstream BURNIE-dilution concern (BURNIE
is off the direct ETH/stETH spine but redeemable against sDGNRS/vault backing) is bounded: one box per
real decimator claimed entry; on the redemption side the per-(wallet,day) base is capped 160 ETH
(sDGNRS:1081) and there is a 50%/day supply cap — so a keeper cannot mint UNBOUNDED dilutive BURNIE that
downstream dilutes the ETH backing. The issuance scales ONLY with real burn activity (390 FC-390-06).

**(iv) `_mintPriceInContext()` reproduces `mintPrice()` exactly → caller cannot SKEW the bounty + the
ETH-value is price-independent** (DecimatorModule:376; the redemption side reads `game.mintPrice()`
directly :812). The BURNIE-per-ETH conversion `PRICE_COIN_UNIT / mintPrice` cancels the price so the
ETH-VALUE delivered is constant across the price curve — confirmed by the DecimatorBountyRegression
"ETH-value holds across price curve" rule (test/fuzz/DecimatorBountyRegression.t.sol:148-156).

**(v) Green-baseline anchor + the UN-NETTED real-gas item:** the 5 pinned DecimatorBountyRegression rules
(per-box :134, scales :162, no-pay-already-claimed/non-winner :180, no-pay-post-gameover :192,
ETH-value-holds + `bounty << 500 BURNIE burn cost` :148-156) pin the DECIMATOR bounty (15e12) at the
0.5-gwei reference. **UN-NETTED (routed test-hardening note, NOT a contract change):** (1) the regression
pins `faucet << burn cost` but NOT the explicit real-gas-net-negative-after-illiquidity number (the 10x/
40x/100x × 0.30-illiquidity multiplier above is a closed-form argument, not a pinned oracle); (2) the
REDEMPTION bounty (24e12) has NO dedicated regression mirror of the 5 decimator rules — the redemption
bounty economics rest on the trace above + the shared-shape argument. A later test phase COULD add a
redemption-bounty regression + a real-gas-net-negative assertion; both are oracle-completeness items, not
contract defects.

**Provisional verdict: REFUTED (net-negative at all real gas + un-manufacturable + issuance bounded).**
NOT a hand-wave — the closed-form real-gas + illiquidity + un-manufacturability accounting is recorded;
the 2 un-netted oracle items are routed.

---

## 4. ACCESS-04 / FC-393-03 — partial-balance burst solvency: dedicated same-block leg accounting (the MED prime)

**PROPERTY:** under an adversarial sequence of MANY partial-balance LIVE claims in ONE block,
Σ(legs over the burst) == Σ(rolled) == Σ(released `_pendingRedemptionEthValue`), and the MAX(175%)
reservation covers each leg so an ETH-balance drain merely SHIFTS the deficit to the stETH leg of the
same held reservation (GAME pulls the remainder fail-closed) — never stranding ETH (left unreleased) or
under-pulling stETH.

**The legs at the frozen source (`_claimRedemptionFor` @sDGNRS):**
- `totalRolledEth = (claim.ethValueOwed * roll) / 100` (the per-claim rolled value, :822).
- Branches sum to `totalRolledEth` EXACTLY: gameOver `ethDirect = total` (:835); live full
  `ethDirect + lootboxEth = total` (:837-838); live dust `ethDirect + forfeitEth = total`
  (`forfeitEth = old lootboxEth`, :846-847).
- **The release is the EXACT rolled amount, ONCE, BEFORE any leg call:**
  `_pendingRedemptionEthValue = uint96(_pendingRedemptionEthValue - totalRolledEth)` (:854), then
  `delete pendingRedemptions[player][day]` (:857) — so a re-entrant re-claim of the same slot is
  impossible (`claim.ethValueOwed == 0 → return false` :823).
- **Each leg recomputes a FRESH balance and clamps ETH to `min(bal, legAmount)`:** lootbox
  `bal = address(this).balance; ethForLootbox = bal < lootboxEth ? bal : lootboxEth;
  resolveRedemptionLootbox{value: ethForLootbox}(…)` (:880-884); direct
  `ethForDirect = min(bal, ethDirect); creditRedemptionDirect{value: ethForDirect}(player,…)` (:888-892);
  forfeit `ethForForfeit = min(bal, forfeitEth); creditRedemptionDirect{value}(address(this),…)`
  (:896-900).
- **The GAME pulls the remainder as stETH, fail-closed:** `stethPortion = amount - msg.value;
  if (stethPortion != 0) { if (!steth.transferFrom(msg.sender, address(this), stethPortion)) revert E(); }`
  — `resolveRedemptionLootbox` @LootboxModule:932-936, `creditRedemptionDirect` @:1009-1011. So each
  leg moves the FULL `legAmount` of VALUE (ETH on hand + stETH remainder), regardless of how depleted
  `address(this).balance` is; a short stETH balance reverts the whole tx.

**Adversarial same-block burst (the interleavings spelled out):**
1. **Many claims drain `address(this).balance` progressively.** Claim #1's legs send `min(bal, leg)`
   ETH; if `bal` is ample, ETH covers the leg. As the burst proceeds, `bal` falls. Eventually a claim's
   ETH leg clamps to a partial amount (`bal < legAmount`), and the GAME pulls the rest as stETH. At the
   extreme, `bal → ~0` so a claim's ETH legs clamp to ~0 and the WHOLE roll comes from stETH. In ALL
   cases the leg moves the full `legAmount` of value (ETH + stETH), so Σ(legs) == Σ(rolled) over the
   burst — the ETH/stETH SPLIT shifts, but the TOTAL does not.
2. **A claim whose stETH `transferFrom` would exceed the held reservation.** The MAX(175%) reservation
   was segregated OUT of the game at submit (`pullRedemptionReserve` → sDGNRS, the `(ethBase * MAX_ROLL)
   / 100` segregation @sDGNRS:742/:1046-1056) and held as sDGNRS's ETH+stETH. The reservation per burn is
   `base × 175%`; the actual rolled is `base × roll` with `roll ∈ [25,175]`, so `rolled ≤ MAX
   reservation`. The release at claim lowers segregation by the rolled amount (:854), leaving the
   `MAX − rolled` over-pull as free backing. Because the reservation (ETH+stETH ≥ Σ MAX ≥ Σ rolled) was
   physically held, the stETH remainder for any leg is ALWAYS coverable — `steth.transferFrom` cannot
   under-pull (it pulls exactly `legAmount − ethOnHand`, and the held stETH ≥ that by the reservation
   bound). If a leg's stETH balance were somehow short, `transferFrom` reverts and the WHOLE claim
   unwinds (the :854 release is rolled back) — fail-closed, no partial strand.
3. **No ETH stranded:** the dust-forfeit branch comment (:893-895) makes the conservation explicit — the
   full rolled amount LEAVES the contract (direct half to player + forfeited half to sDGNRS), so it
   reconciles exactly with the `_pendingRedemptionEthValue` release; no ETH is left unreleased.

**Σ identity (the burst-solvency bound):** over any same-block burst of K live claims,
Σ(ethDirect + lootboxEth + forfeitEth) = Σ(totalRolledEth) = Σ(reduction of `_pendingRedemptionEthValue`)
— each claim is an independent atomic decrement + delete + leg-set, and the legs each move the full
`legAmount` (ETH-clamped + stETH-remainder). An earlier claim draining `address(this).balance` only
changes the ETH/stETH FUNDING MIX of a later claim's legs; it cannot change the TOTAL value moved or
under-release the segregation. **No strand, no under-pull.**

**CONSISTENT with the 390 FC-392-08 / FC-393-03 solvency-half (REFUTED at 390 §2c):** each leg recomputes
a fresh `bal`, GAME pulls the remainder fail-closed, Σ legs == Σ rolled == Σ released, MAX reservation
covers. This NET-2 pass attacks the ACCESS half (the cross-chunk / same-block race + the FC-392-08
cap-RMW-raced-across-chunks half routed here) and confirms the burst cannot strand/under-pull. The
FC-392-08 cross-chunk cap-RMW race is closed because `resolveRedemptionLootbox` credits the pool by
`amount` BEFORE the chunk loop (LootboxModule:945-947) and the chunks run sequentially in ONE delegatecall
frame (:951-957) with the ETH-spin reading/writing fresh storage per chunk (no deferred memory accumulator
to race) — so even within one claim's multi-chunk resolution there is no cross-chunk cap-RMW race.

**UN-NETTED (routed test-hardening note, NOT a contract change):** there is no dedicated SAME-BLOCK-BURST
multi-claim burst-solvency oracle (the existing `RedemptionStethFallback.t.sol` 10/10 + `RedemptionAccounting.t.sol`
EXERCISE the single-claim partial-balance legs + the V62-03 CEI class, and `RedemptionAccounting`
EXERCISES per-(player,day), but neither runs an adversarial K-claim same-block drain). A later test phase
COULD add a same-block-burst invariant; oracle-completeness, not a contract defect (the burst-solvency is
proven above by trace + the EXERCISED single-claim tests + the MAX-reservation bound).

**Provisional verdict: REFUTED (burst cannot strand ETH or under-pull stETH; Σ identity holds).**

---

## 5. ACCESS-03 / FC-393-01 — forced claim-timing: the adjacent-level MAGNITUDE question (NOT the timing model)

**PROPERTY:** timing is by-design ([[lootbox-resolution-timing-by-design]] — DO NOT re-litigate); the
verdict turns on whether any reward MAGNITUDE / target-level distribution diverges enough between ADJACENT
levels to make a FORCED resolution materially harmful to the winner.

**The forced-timing mechanism at the frozen source:** a third party can force a winner's live-game
decimator claim to resolve at a LIVE `level` the winner did not choose. The lootbox award reads the LIVE
`level`: `uint24 startLevel = level + 1` for the whale-pass queue (`_applyWhalePassStats(winner,
startLevel)` + `_queueTicketRange(winner, startLevel, 100, fullHalfPasses, false)` @DecimatorModule:655-658),
and the sub-half-pass remainder routes to `resolveLootboxDirect` whose `_rollTargetLevel(currentLevel,
seed)` reads the LIVE `currentLevel` (@LootboxModule:884). The win/loss + EV-multiplier are FROZEN
(`round.rngWord` snapshotted at `runDecimatorJackpot` :277; `winBucket = e.bucket` sealed at burn time
:397; `_minScoreForBucket(winBucket, lvl)` :408-410) — so the only thing forced timing controls is the
LEVEL ANCHOR the reward tickets land at.

**The adjacent-level magnitude analysis (`_rollTargetLevel` @LootboxModule, re-read):**
```
rangeRoll = uint16(seed) % 100;
if (rangeRoll < 20)  targetLevel = baseLevel + (uint16(seed>>24) % 46) + 5;   // 20%: far 5-50 ahead
else                 targetLevel = baseLevel + (uint8(seed>>16) % 5);          // 80%: near 0-4 ahead
```
The OFFSET DISTRIBUTION (near 0-4 @80%, far 5-50 @20%) is fully determined by the FROZEN `seed` — forced
timing does NOT change it. Forced timing changes ONLY `baseLevel = currentLevel` (the anchor). So a forced
EARLIER resolution lands the SAME offset distribution onto a LOWER anchor (tickets for levels closer to
the current game level), and a forced LATER resolution lands it onto a HIGHER anchor.

- **Direction of harm:** a forced EARLIER resolution gives the winner tickets at levels CLOSER to the
  current game level — these resolve sooner (higher probability of being reached / winning sooner), which
  is BENEFICIAL or NEUTRAL for the winner, not harmful. The whale-pass `startLevel = level + 1` likewise
  starts the pass nearer the current level on an earlier resolution — earlier coverage, not later.
- **Adjacent-level magnitude:** ticket-price / jackpot-reward jumps exist at MILESTONE levels (e.g. the
  ~0.16→0.24 ETH ticket-price jump around L99→L100 the council noted), but those price jumps come WITH
  corresponding jackpot-reward jumps (the price funds the bigger pool) — the EV the winner's lootbox
  buys at the higher level is not strictly worse; and critically the winner's REWARD MAGNITUDE
  (`amountWei`, the decimator claim value) is FROZEN at resolution (`round.poolWei` / the winner's sealed
  entry), NOT recomputed from the live level — only the TARGET-LEVEL the tickets are queued at moves. So
  a griefer cannot REDUCE the winner's reward magnitude by forcing the timing; they can only shift WHICH
  near-future levels the tickets cover, and the offset distribution is frozen-seed-invariant.
- **No outcome steering:** the win/loss + EV multiplier are frozen-seed-determined and mix `player` not
  `msg.sender` — a third party cannot re-roll either by being the caller or by timing.

**Magnitude reasoning conclusion:** the reward MAGNITUDE is frozen; only the target-level ANCHOR moves
with forced timing; the offset distribution is frozen-seed-invariant; forced EARLIER resolution is
beneficial/neutral (closer-level tickets); no adjacent-level divergence makes a forced resolution
materially HARMFUL to the winner. This is NOT a "timing is by-design so fine" dismissal — it is settled on
the magnitude: forced timing cannot reduce the winner's frozen reward, and the only controllable degree
of freedom (the level anchor) shifts the reward toward closer (better-or-neutral) levels.

**Provisional verdict: BY-DESIGN / REFUTED (forced timing cannot materially reduce the winner's reward;
magnitude inert; outcome frozen). MONITOR posture: it remains a genuinely NEW externally-forceable timing
surface — recorded so a future change to the level-dependent reward magnitude would re-open the question.**

---

## 5b. ACCESS-01 / FC-393-02 — forfeit-to-self timing (per-victim extractability?)

**PROPERTY:** the dust lootbox (<0.01 ETH half) forfeits to sDGNRS's OWN claimable (raising backing for
ALL holders); a keeper choosing WHICH redemptions to settle could bias WHEN forfeits land vs full
lootboxes resolve — confirm the per-claim split is DETERMINISTIC (no per-victim value extraction), only
benign timing of uniform backing accrual.

**Attack tried:** can a keeper, by choosing the settle order/selection, extract value FROM a specific
victim into their own pocket, or steer a forfeit to/from a specific holder?

**RESULT:** the dust/full split is DETERMINISTIC from the FIXED `roll` (`redemptionPeriods[day]`, fixed at
resolution :771) + the player's OWN owed value: `lootboxEth = totalRolledEth - ethDirect`; if
`lootboxEth < MIN_REDEMPTION_LOOTBOX_ETH (0.01 ether)` → `forfeitEth = lootboxEth; lootboxEth = 0`
(:843-848). The keeper's only degree of freedom is WHICH (already-resolved) claims to settle and WHEN —
the split itself is not keeper-controllable. The forfeit credits sDGNRS's own claimable (`creditRedemptionDirect{value}(address(this), forfeitEth)` :898), raising backing for ALL holders UNIFORMLY
(no per-victim target). So there is NO per-victim value extraction — only benign timing of uniform
backing accrual. The dust-drop policy itself is by-design ([[redemption-dust-lootbox-drop-bydesign]]); the
question here is strictly per-victim extractability, and it is absent. CONSISTENT with the 390 FC-393-02
solvency-half (BY-DESIGN/REFUTED).

**Provisional verdict: BY-DESIGN / REFUTED (deterministic split; no per-victim extraction; uniform
backing accrual).**

---

## 6. ACCESS-05 — gate + reentrancy intactness enumeration (every new/widened entrypoint)

**PROPERTY:** for EACH entrypoint, (i) the freeze/rngLocked/liveness/gameOver gate, and (ii) the
ETH/stETH reentrancy CEI, are intact; (iii) the Game-side callees are SDGNRS-gated;
`distributeYieldSurplus` is internal-only and not an independently-exploitable lever.

| Entrypoint | (i) gate | (ii) reentrancy / CEI | cite (`a8b702a7`) |
|------------|----------|------------------------|-------------------|
| `claimDecimatorJackpot` / `Many` | `if (prizePoolFrozen) revert E()` (reverts during the VRF freeze window) | no ETH leaves — resolution into `claimablePool`/`futurePrizePool`; `e.claimed = 1` set BEFORE the lootbox-resolve delegatecall (:399) so no re-settle; the lootbox-resolve delegatecall is into the GAME's OWN module (trusted) | DecimatorModule:298/:329/:399 |
| `claimRedemption` / `Many` (post-gameOver) | gameOver self-claim-only (`isGameOver && player != msg.sender` revert/continue) | slot `delete pendingRedemptions[player][day]` (:857) + `_pendingRedemptionEthValue -= totalRolledEth` (:854) lowered BEFORE the untrusted `_payEth(player, ethDirect)` (:830); `_payEth` sends stETH FIRST, untrusted ETH `.call` LAST (:1098 region — the V62-03/SOLVENCY-01 reasoning in the comment) | sDGNRS:775/:793/:854/:857/:830/_payEth |
| `claimRedemption` / `Many` (live) | `redemptionPeriods[day] != 0` (resolved); the burn-side gate `BurnsBlockedBeforeDailyRng` pins the pool to a drawn day (:991) | slot deleted + segregation lowered BEFORE the legs forward to the GAME; the GAME callees pull the stETH remainder via `transferFrom` (reverts if short) — no ETH pushed at the player; the lootbox seed `hash2(rngWordForDay(day+1), player)` mixes `player` not `msg.sender` (:878) | sDGNRS:854/:857/:878/:884/:892 |
| `claimCoinflipCarry` | `if (degenerusGame.rngLocked()) revert RngLocked()` (:759) — same lock as the rebuy toggle; settles RESOLVED days first then pays the SETTLED carry; cannot mint pending-day (still-at-flip-risk) stake | mints to `player`; no ETH leg; `state.autoRebuyCarry` debited (:773-775) BEFORE the mint (:777); `_resolvePlayer` bounds the caller | BurnieCoinflip:759/:773-777 |

**Game-side callees:** `resolveRedemptionLootbox` (@LootboxModule:926) and `creditRedemptionDirect`
(@:1004) both gate `if (msg.sender != ContractAddresses.SDGNRS) revert E()` (:927/:1005) — reachable only
from sDGNRS. **`distributeYieldSurplus`:** reachable ONLY internally from advanceGame
(`_distributeYieldSurplus`, AdvanceModule) — NO external Game stub — and credits-only when
`totalBal > obligations` (its obligations sum reads all live pools + claimablePool fresh, so a reentrant
call cannot read in-flight stETH as surplus). NOT an independently-exploitable permissionless lever.
**`_payoutWithStethFallback`** (@DegenerusGame.sol:1888) — the Game's own claim payout — was reordered
(53cd25cf) to move the stETH leg out FIRST (:1900-1907) and run the untrusted ETH `.call` LAST
(:1910-1914), closing the V62-03 in-flight-stETH double-count (the comment :1891-1894).

**FC-390-03 ACCESS half (mid-batch gameOver/frozen boundary):** `claimDecimatorJackpotMany` caches
`bool over = gameOver` ONCE (:341) with the explicit invariant comment (:335-337); `claimRedemptionMany`
caches `bool isGameOver = game.gameOver()` ONCE (:791); the resolution-into-claimable legs hold no
untrusted ETH hook that could flip the boundary mid-loop — so no permissionless batch can split
inconsistently across the gameOver/frozen boundary. (Solvency half REFUTED at 390; the ACCESS half holds
here.)

**Attack tried:** a missing/widened gate or an open reentrancy path across the ETH/stETH legs on any new
entrypoint. RESULT: every entrypoint gates its window; every untrusted ETH `.call` runs LAST after the
slot delete + ledger debit + stETH transfer; the callees are SDGNRS-gated; `distributeYieldSurplus` is
internal-credits-only. **No missing/widened gate; no open reentrancy path.**

**Provisional verdict: REFUTED (all gates + CEI intact on every new/widened entrypoint).**

---

## 6b. ACCESS-05 / FC-393-04 (inherited FC-392-20) — widened claim-loop gas worst-case

**PROPERTY:** no realistic actor can force a many-hundred-day cold-SLOAD walk into a GAS-SENSITIVE caller
(the advanceGame chain specifically) under the new packed masked sub-word layout — the worst-case
365/1460 loop is reachable only by a caller paying their OWN gas, never bricking advanceGame.

**At the frozen source:** the windows widened (`COIN_CLAIM_DAYS = 365` :136, `AUTO_REBUY_OFF_CLAIM_DAYS_MAX
= 1460` :138; counters `uint16`/`uint32` :137-138 region) over the new packed storage (day-result is a
masked sub-word read `uint8(coinflipDayResultPacked[day >> 5] >> ((day & 31) * 8))` :1093; 32 days/slot).
Claims are USER-PAID + OUT of the advanceGame chain. The advanceGame-chain sDGNRS auto-settle in
`processCoinflipPayouts` (`onlyDegenerusGameContract`, once/day) walks `deep = false` in both branches —
bounded by `windowDays` (365) — and in steady state processes ~1 day/advance. The 1460-deep + 365-window
perma-brick gas was pinned by a dedicated regression (0a2209d4).

**Attack tried:** force a 365/1460 cold-SLOAD walk into advanceGame (a liveness brick). RESULT: the
advanceGame-chain auto-settle is `deep = false` (≤365, ~1 day/advance steady state); the unbounded
365/1460 walk is reachable ONLY by a self-paid `claimCoinflips`/`claimCoinflipCarry` caller (their own
gas), never by the advanceGame chain. No new advanceGame brick. CONSISTENT with FC-392-20 INFO at 392.

**UN-NETTED (routed test-hardening note, NOT a contract change):** a FRESH packed-layout worst-case gas
measurement (the 365/1460 walk over the NEW masked sub-word layout) is not pinned beyond the 0a2209d4
perma-brick regression — a later gas phase COULD add a packed-layout worst-case measurement; oracle/gas
completeness, not a contract defect.

**Provisional verdict: REFUTED / INFO (off the gas-sensitive chain; caller-paid; auto-settle bounded).**

---

## 7. Council fold-in (NET 1 — read AFTER the independent pass above)

After the independent NET-2 pass, the NET-1 council outputs (`393-01-COUNCIL-NET.md` +
`council/access.gemini.txt`) were read. `codex` SKIPPED (hard usage-limit cap — recorded in `skipped[]`,
post-reset re-run flagged → 396). `gemini` is on record: **VERIFIED SOUND across ALL of ACCESS-01..05 +
FC-393-04 — 0 findings**, with concrete per-item traces and the real-gas numbers the prompt charged for.

| Item | NET-2 (Claude) | NET-1 (gemini) | convergence |
|------|----------------|----------------|-------------|
| ACCESS-01 | REFUTED (beneficiary-only per entrypoint) | SOUND (value to `player`, never `msg.sender`) | CONVERGENT |
| ACCESS-02 | REFUTED (net-negative all real gas + un-manufacturable + bounded) | SOUND (40x@20gwei, 10x@5gwei, ~30% liquid, un-manufacturable) | CONVERGENT — same real-gas numbers |
| ACCESS-03 / FC-393-01 | BY-DESIGN/REFUTED (magnitude inert; frozen reward; offset distribution frozen-seed-invariant) | INERT (adjacent-level jumps are milestone reward jumps; forced earlier beneficial/neutral; frozen seed immunizes) | CONVERGENT |
| ACCESS-04 / FC-393-03 | REFUTED (Σ legs == Σ rolled == Σ released; MAX reservation covers; ETH-drain shifts to stETH leg) | SOUND (`_pendingRedemptionEthValue` lowered by exact `totalRolledEth`; MAX_ROLL 175% reservation shifts deficit to stETH leg) | CONVERGENT |
| ACCESS-05 | REFUTED (gates + CEI + SDGNRS-gated callees + internal-only yield-surplus) | SOUND (`prizePoolFrozen`, `rngLocked`, self-claim-only, CEI, stETH-first/ETH-last, SDGNRS-gated callees) | CONVERGENT |
| FC-393-02 | BY-DESIGN/REFUTED (deterministic split; no per-victim extraction) | SOUND (forfeit-to-self deterministic; no per-victim extraction) | CONVERGENT |
| FC-393-04 / FC-392-20 | REFUTED/INFO (caller-paid; off advanceGame chain; auto-settle bounded) | SOUND (packed storage keeps walks cheap; auto-settle O(1) steady state; caller-paid isolated) | CONVERGENT |
| FC-390-03 (ACCESS half) | REFUTED (batch caches over/frozen once; no boundary split) | SOUND (within ACCESS-05 gate trace) | CONVERGENT |
| FC-390-06 (ACCESS half) | REFUTED (issuance bounded; one box/real burn; 160-ETH/50%-day caps) | SOUND (within ACCESS-02 un-manufacturability) | CONVERGENT |
| FC-392-08 (ACCESS half) | REFUTED (pool credited before chunks; chunks sequential one frame; no cross-chunk race) | SOUND (within ACCESS-04/05) | CONVERGENT |

**Cite-drifts reconciled (§0):** gemini's redemption bounty `24e12` was CORRECT (the plan/surface-map
"both 15e12" was wrong); the carry mint entry is :754 / mint :777 (neither @366 nor :787). The
net-negative-vs-real-gas conclusion holds at the TRUE constants. **No council-only divergent lead** —
gemini returned 0 findings, all convergent-SOUND with NET 2. Both nets converge on a no-finding verdict
for every item. The `codex` second-source is owed (post-reset re-run → 396).

---

## 8. NET-2 provisional verdict summary (independent of the council, folded after)

| ITEM | NET-2 provisional verdict | settling bound / cite (`a8b702a7`) |
|------|---------------------------|-------------------------------------|
| ACCESS-01 | REFUTED | beneficiary-only per entrypoint (§2): DecimatorModule:316/:459, sDGNRS:884/:892/:830, BurnieCoinflip:777 |
| ACCESS-02 | REFUTED | net-negative 10x/40x/100x @5/20/50 gwei × 0.30 illiquidity + un-manufacturable + FC-390-06 bound (§3): DecimatorModule:117/:364-376, sDGNRS:348/:810-814 |
| ACCESS-03 / FC-393-01 | BY-DESIGN/REFUTED (MONITOR posture) | frozen reward magnitude + frozen-seed-invariant offset distribution; forced earlier = beneficial/neutral (§5): LootboxModule:`_rollTargetLevel`/:884, DecimatorModule:655-658/:277/:397 |
| ACCESS-04 / FC-393-03 | REFUTED | Σ legs == Σ rolled == Σ released; MAX(175%) reservation covers; ETH-drain shifts to stETH leg fail-closed (§4): sDGNRS:822/:854/:880-900, LootboxModule:932-936/:1009-1011 |
| ACCESS-05 | REFUTED | gates + CEI per entrypoint + SDGNRS-gated callees + internal-only yield-surplus (§6): DecimatorModule:298/:399, sDGNRS:775/:854/:857, BurnieCoinflip:759, LootboxModule:927/:1005, DegenerusGame.sol:1888 |
| FC-393-02 | BY-DESIGN/REFUTED | deterministic dust/full split; no per-victim extraction; uniform backing accrual (§5b): sDGNRS:843-848/:898 |
| FC-393-04 / FC-392-20 | REFUTED/INFO | caller-paid; off advanceGame chain; auto-settle deep=false bounded (§6b): BurnieCoinflip:136-138/:1093 |
| FC-390-03 (ACCESS half) | REFUTED | batch caches over/frozen once; no boundary split (§6): DecimatorModule:335-341, sDGNRS:791 |
| FC-390-06 (ACCESS half) | REFUTED | issuance bounded; one box/real burn; 160-ETH/50%-day caps (§3): DecimatorModule:364-370, sDGNRS:1081/:810-814 |
| FC-392-08 (ACCESS half) | REFUTED | pool credited before chunks; chunks sequential one frame; no cross-chunk cap-RMW race (§4): LootboxModule:945-957 |

**Routed un-netted test-hardening items (NOT contract changes):** (1) a redemption-bounty regression
mirror of the 5 decimator rules + an explicit real-gas-net-negative-after-illiquidity assertion
(ACCESS-02); (2) a same-block-burst multi-claim burst-solvency invariant (ACCESS-04); (3) a fresh
packed-layout worst-case gas measurement of the 365/1460 walk (FC-393-04). All oracle/gas completeness.

**NET 2 is on record, independent of the council, with a per-item attack attempt + provisional verdict
over the full phase-393 permissionless-composition surface; the keeper-bounty given a dedicated real-gas
economic treatment; the partial-balance burst-solvency given a dedicated same-block leg-accounting
treatment; the forced-timing settled on the magnitude question; the gate/reentrancy enumerated; the
council leads folded in at §7.** `git diff a8b702a7 -- contracts/` EMPTY — read-only over the frozen
subject throughout.
