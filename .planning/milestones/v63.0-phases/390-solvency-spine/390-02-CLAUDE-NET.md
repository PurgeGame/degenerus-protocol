# 390-02 — NET 2 (Claude Adversarial Net) — SOLVENCY-SPINE (SOLV-01..07 + FC-390-01..07 + cross-refs)

**Subject (byte-frozen):** `a8b702a7` (contracts tree `2934d3d8987a09c5f073549a0cb499f6c5f28620`).
`git diff a8b702a7 -- contracts/` EMPTY before and after this task (all source read via
`git show a8b702a7:contracts/<File>.sol`, working tree ignored).
**Net:** NET 2 = the deep Claude adversarial net. Run INDEPENDENTLY first — each identity/conservation
claim attacked with a concrete reachable call sequence (multi-tx where ordering matters) BEFORE the
council outputs (390-01) were read. The council fold is at §C (end), as the plan requires.
**Baseline (the audit oracle):** `test/REGRESSION-BASELINE-v63.md` — forge **854/0/110**, expected-red
name-set strictly EMPTY. Redemption coverage anchors: `RedemptionStethFallback.t.sol` (10/10
branch-proofs, V62-03 CEI class EXERCISED) + `RedemptionAccounting.t.sol` (per-(player,day) EXERCISED).
The legacy `RedemptionInvariants` 7-INV harness is the 388-02 #2 SUPERSEDED HOLE — NOT relied on here.
**Posture:** AUDIT-ONLY. No contract source touched. A CONFIRMED finding is documented + routed; not
fixed in this phase.

---

## A. The two solvency identities under attack (restated from frozen source)

**Game identity (DegenerusGame header 18-19 + DegenerusGameStorage.sol:357-366):**
> I1: `address(this).balance + steth.balanceOf(this) >= claimablePool`
> I2: `claimablePool == Σ (claimable + afking halves of balancesPacked[*])`

Both the per-player claimable winnings AND prepaid afking ride inside the single `claimablePool`
uint128. The prize pools (current/next/future), `yieldAccumulator`, and the pending freeze pools are
SEPARATE obligations layered on top in the yield-surplus view — NOT inside `claimablePool`. **Whale-pass
value (`whalePassCost`) is a futurePrizePool obligation, OUTSIDE the I2 claimablePool identity.** This
caveat is load-bearing for SOLV-07.

**sDGNRS identity (StakedDegenerusStonk.sol):** backing per token =
`(ethBal + stethBal + claimableEth − _pendingRedemptionEthValue) / totalSupply`
(the `totalMoney` read at :674, :924, :1023). `_pendingRedemptionEthValue` is the physically segregated
reserve for unresolved/unclaimed gambling-burn redemptions, EXCLUDED from regular-burn backing so it is
never double-spent.

The attack method: for each spine touch, find a path that (a) credits `claimablePool` without a backing
arrival, (b) releases segregated ETH without a paired obligation move, (c) double-counts the same wei
into two obligations both later paid, or (d) reads in-flight value as free backing across a reentrant
call. Each item records PROPERTY · ATTACK tried · STATE VAR + file:line@`a8b702a7` · settling bound ·
provisional verdict.

---

## B. Per-item independent adjudication

### SOLV-01 — `claimablePool == Σ claimable + afking` across every changed credit/debit

**PROPERTY:** every packed-balance move on the spine pairs an equal `claimablePool` move.
**ATTACK:** enumerate the change inventory A1..G5 and find a `_creditClaimable` / `_debitClaimable`
without a paired `claimablePool +=/-=`, or a manual delta-fold that drops a credit.

Touch-by-touch trace (STATE VAR `claimablePool` uint128):
- **claimWinnings CEI** (`DegenerusGame.sol:1247-1248`): `_debitClaimableAndAfking(player, claimDebit, afking)`
  then `claimablePool -= uint128(payout)` where `payout = claimDebit + afking`. Paired exactly, BEFORE
  the untrusted call. ✔
- **creditRedemptionDirect** (`DegenerusGameLootboxModule.sol:1013-1014`): `_creditClaimable(player, amount)`
  then `claimablePool += uint128(amount)`. Value pulled in first (L1009-1012), then paired. ✔
- **pullRedemptionReserve ETH leg** (`DegenerusGame.sol:1582-1583`): `_debitClaimable(SDGNRS, amount)`
  then `claimablePool -= uint128(amount)`. Paired; stETH leg (L1594) does NO game move (sDGNRS's own
  stETH backs it) so no debit needed — correct. ✔
- **JackpotModule daily delta-fold** (`DegenerusGameJackpotModule.sol:1117-1120`): the inner loop
  accumulates `liabilityDelta += claimDelta` per bucket (only the claimable portion — see SOLV-07),
  then ONE `claimablePool += uint128(liabilityDelta)`. Each `_creditClaimable` inside `_payNormalBucket`
  (:1229) and `_processSoloBucketWinner` (:1268/:1277) is captured into `claimDelta`/`liabilityDelta`. ✔
- **JackpotModule yield-surplus fold** (`:707-713`): 3 `_creditClaimable(VAULT/SDGNRS/GNRUS, quarterShare)`
  then `claimablePool = claimablePoolCached + uint128(quarterShare * 3)` — captures all three. ✔
- **GameOverModule deity refunds** (`DegenerusGameGameOverModule.sol:117/130`): `_creditClaimable(owner, refund)`
  inside the loop, then `claimablePool += uint128(totalRefunded)` once. ✔ Terminal decimator spend
  (`:169`) `claimablePool += uint128(decSpend)` paired with `runTerminalDecimatorJackpot` credits.
- **_settleShortfall** (`DegenerusGameStorage.sol:867`): "Each debit pairs an equal `claimablePool`
  debit" — single sink, sentinel-preserving. ✔

**SETTLING BOUND:** every enumerated touch pairs a `claimablePool` move; the manual JackpotModule fold
captures every `_creditClaimable` on each path into the per-path delta (SOLV-07 confirms the solo split
folds only the ETH portion). No unpaired credit/debit found. **VERDICT: REFUTED (identity holds).**

### SOLV-02 — sDGNRS backing identity (balance + stETH ≥ obligations) across the rework

**PROPERTY:** `totalMoney = ethBal + stethBal + claimableEth − _pendingRedemptionEthValue` correctly
states free backing; no path inflates `_pendingRedemptionEthValue` (uint96) or `poolBalances` (uint128)
beyond width (a truncating cast would UNDERSTATE segregated ETH → over-state free backing → drift).
**ATTACK:** drive `_pendingRedemptionEthValue` past 2^96 via repeated submits; or find a release/submit
cast that truncates.

- The backing read is consistent at all 3 sites (StakedDegenerusStonk.sol:674, :924, :1023) — same
  formula. `_pendingRedemptionEthValue` subtracted so the segregated reserve never backs a regular burn. ✔
- **Width bound:** `_pendingRedemptionEthValue` is real-ETH bounded. Per-(wallet,day) base is capped at
  `MAX_DAILY_REDEMPTION_EV` = 160 ETH (`:1081`), × `MAX_ROLL`/100 (175%) = 280 ETH per wallet-day
  segregated MAX; cumulative across all wallets is bounded by the total ETH ever in the protocol
  (~1.2e26 wei) ≪ uint96 max ~7.9e28. Unreachable overflow. The cast sites operate on CHECKED arithmetic:
  submit `uint96(_pendingRedemptionEthValue + maxIncrement)` (:1066), resolve
  `uint96(_pendingRedemptionEthValue − segregatedMax + rolledEth)` (:745), claim
  `uint96(_pendingRedemptionEthValue − totalRolledEth)` (:854) — each on a checked expression that
  reverts on under/overflow before the narrowing. ✔
- **poolBalances (uint128):** sDGNRS token amounts (BPS slices of INITIAL_SUPPLY 1e30) ≪ uint128 ~3.4e38;
  pool transfers clamp to available balances (council-cited :548-559). ✔ (Folds FC-389-02 / FC-389-08
  solvency-conservation half — REFUTED at 389; re-confirmed here at the spine.)

**SETTLING BOUND:** the segregation read excludes pending; every narrowing is on a checked result with a
real-ETH/supply bound far under the type width. **VERDICT: REFUTED (identity holds). FC-389-02/-08
solvency half: REFUTED.**

### SOLV-03 — submit/claim conservation (`ethDirect + lootboxEth + forfeitEth == totalRolledEth`)

**PROPERTY:** in EVERY branch of `_claimRedemptionFor` the three legs sum to `totalRolledEth`, and
`_pendingRedemptionEthValue -= totalRolledEth` (:854) releases exactly that.
**ATTACK:** find a branch where the legs sum ≠ rolled, or the release ≠ leg movement (strand/leak).

`_claimRedemptionFor` (StakedDegenerusStonk.sol:821-903), `totalRolledEth = ethValueOwed*roll/100` (:828):
- **gameOver branch** (:834-835): `ethDirect = totalRolledEth`; lootboxEth = forfeitEth = 0 →
  sum = totalRolledEth. Push via `_payEth(player, ethDirect)` (:864). ✔
- **live full-lootbox branch** (:837-838): `ethDirect = totalRolledEth/2`,
  `lootboxEth = totalRolledEth − ethDirect` → sum = totalRolledEth (floor split exact by construction).
  forfeitEth = 0. ✔
- **live dust-forfeit branch** (:845-848): when `lootboxEth < MIN_REDEMPTION_LOOTBOX_ETH`,
  `forfeitEth = lootboxEth; lootboxEth = 0` → sum = ethDirect + 0 + (old lootboxEth) = totalRolledEth. ✔
- **release** (:854): `_pendingRedemptionEthValue -= totalRolledEth` — exactly the rolled amount. The
  MAX−rolled over-pull (segregated at submit, lowered at resolve :745) stays in sDGNRS as free backing,
  NOT released here. No double-count across the submit↔claim boundary: submit reserves MAX (:1063
  `pullRedemptionReserve(maxIncrement)`), resolve lowers MAX→rolled (:745), claim releases rolled (:854).
- **fail-closed:** if a leg's external send/pull reverts, the whole tx reverts (the :854 decrement and
  :857 slot delete revert too) — value can't be released-but-not-moved. ✔

**SETTLING BOUND:** every branch's legs sum to `totalRolledEth`; the release equals exactly that; the
submit/resolve/claim chain telescopes MAX→rolled with no double-count. **VERDICT: REFUTED.**

### SOLV-04 / FC-390-02 — dust-forfeit self-credit always backed (DEDICATED §6 prime)

**PROPERTY:** `creditRedemptionDirect{value: ethForForfeit}(address(this), forfeitEth)` credits
`forfeitEth` to sDGNRS's OWN game claimable; this credit MUST always be backed by `forfeitEth` of value
actually leaving sDGNRS — never a phantom claimable bump.
**ATTACK (multi-tx, partial-balance):** drain `address(this).balance` below `forfeitEth` (via an earlier
leg / many partial claims in one block) so `ethForForfeit = min(bal, forfeitEth) < forfeitEth`, then
force the GAME-side stETH remainder pull to either (a) revert leaving a half-state, or (b) succeed while
crediting MORE than sDGNRS released (phantom bump).

Trace (StakedDegenerusStonk.sol:897-901 → DegenerusGameLootboxModule.sol:1004-1014):
- sDGNRS computes `bal = address(this).balance; ethForForfeit = min(bal, forfeitEth)` (:898-899), sends
  `{value: ethForForfeit}` with `amount = forfeitEth` (:900).
- GAME `creditRedemptionDirect(player=SDGNRS, amount=forfeitEth)`: guard `msg.value > amount` reverts
  (:1006); `stethPortion = amount − msg.value = forfeitEth − ethForForfeit` (:1009); if non-zero,
  `steth.transferFrom(SDGNRS, GAME, stethPortion)` — **reverts the whole tx if it fails** (:1011); THEN
  `_creditClaimable(SDGNRS, forfeitEth)` + `claimablePool += forfeitEth` (:1013-1014).
- **Result:** the credit of `forfeitEth` is ALWAYS = `ethForForfeit` (ETH that arrived as msg.value) +
  `stethPortion` (stETH pulled from sDGNRS) = `forfeitEth` total value that LEFT sDGNRS. Value-in-before-
  credit (strict CEI). Attack (a): the transferFrom revert unwinds the whole claim tx — fail-closed, no
  half-state. Attack (b): a credit > released is impossible — the GAME pulls EXACTLY `forfeitEth −
  msg.value`, never less.
- **MAX-reservation coverage:** can the stETH remainder pull ever lack balance/approval? sDGNRS
  pre-approves GAME for max on both legs (council :431-432 / the funding-mix comment :999). The MAX(175%)
  reservation at submit guarantees sDGNRS holds ETH+stETH ≥ MAX ≥ rolled = ethDirect+lootboxEth+forfeitEth.
  Since `forfeitEth ≤ rolled` and the direct leg + forfeit leg each pull `legAmount − onHandETH` as stETH
  against that same held reservation, the held ETH+stETH always covers the sum of legs (= rolled). If a
  pathological state ever under-pulled, the transferFrom reverts fail-closed — never an over-credit.
- **stETH-leg submit case** (no claimable debited at submit, `pullRedemptionReserve` stETH leg :1594):
  the forfeit credit still nets correctly — the value pulled at the forfeit leg comes from sDGNRS's own
  stETH custody (the same custody the stETH-leg reservation left in place), and `_pendingRedemptionEthValue`
  was released by exactly `totalRolledEth` at :854. No over-credit relative to the segregation released.

**SETTLING BOUND:** the GAME pulls `forfeitEth − msg.value` as stETH and reverts if it can't, so the
`claimablePool += forfeitEth` is exactly backed by `forfeitEth` of ETH+stETH leaving sDGNRS; fail-closed
on shortfall. **VERDICT: REFUTED (dust-forfeit self-credit fully backed under the MAX reservation).**

### SOLV-05 / FC-390-01 — redemption-claim liveness ordering (DEDICATED §6 prime, multi-tx)

**PROPERTY:** `claimRedemption`/`Many` read `isGameOver = game.gameOver()` ONCE (:775/:791); no
strand/double-credit across the `livenessTriggered → gameOver` latch vs `handleGameOverDrain`.
**ATTACK (multi-tx ordering):** the three interleavings the plan names.

Drain anatomy (`DegenerusGameGameOverModule.sol:73-182`): `totalFunds = balance + stETH` (:78);
`reserved = claimablePool` (:85); `preRefundAvailable = totalFunds − reserved` (:86); deity refunds grow
`claimablePool` (:117/:130); **`gameOver = true` latched (:135)**; pools zeroed (:145-148);
`postRefundReserved = claimablePool` (:153); `available = totalFunds − postRefundReserved` (:154);
decimator spend (:166-170); terminal jackpot of `remaining` (:180). Final sweep (:192) sets
`claimablePool = 0` (:206) after 30 days.

**Key structural fact (the load-bearing settle):** redemption ETH is segregated OUT of the game at
SUBMIT — `pullRedemptionReserve` transferred it to the sDGNRS contract (or left it as sDGNRS stETH). So
it is NOT part of the drain's `totalFunds` (the drain comment states this explicitly at :82-84). The
drain therefore reserves ONLY `claimablePool` (player winnings), never the redemption reserve.

- **(a) live claim mined just after the drain's `totalFunds` snapshot but before `gameOver` latches —**
  Impossible WITHIN one tx (EVM atomicity: no other tx executes "between :78 and :135" of the drain's
  call frame). ACROSS txs: the claim is a SEPARATE tx that runs entirely before OR entirely after the
  drain tx. If BEFORE: the live claim's `creditRedemptionDirect`/`resolveRedemptionLootbox` push real
  ETH/stETH INTO the game and bump `claimablePool` (direct) / futurePrizePool (lootbox) — the drain then
  snapshots a `totalFunds`/`claimablePool` that already includes them, so `reserved = claimablePool`
  protects the credited claim. If AFTER: `gameOver` is latched → the claim reads `isGameOver = true` →
  routes the post-game 100% direct PUSH (`_payEth`, paid from sDGNRS's own segregated balance, NOT the
  game ledger). Either way consistent — the drain can never sweep funds a live claim then needs, because
  the live claim's funds are EITHER already in `claimablePool` (counted as reserved) OR paid from
  sDGNRS's segregated reserve (never in the game's `totalFunds`). ✔
- **(b) claim observes `isGameOver = false`, releases `_pendingRedemptionEthValue`, then gameOver latches
  before the credit legs complete (stranded value)?** — Impossible: the release (:854), the slot delete
  (:857), and the credit legs (:882/:890/:900) are all in ONE tx. There is no point where another tx
  (the drain) interleaves. If the drain's tx ran first, the claim's `game.gameOver()` read (a fresh
  cross-contract call at :775) returns true and routes the post-game path — no live release/credit
  mismatch. The single `isGameOver` snapshot is taken at the TOP of the claim tx and is stable for that
  tx's duration. ✔
- **(c) post-gameOver 100% direct path double-paying a claim that already settled live?** — Impossible:
  `_claimRedemptionFor` `delete pendingRedemptions[player][day]` (:857) on the live settle; a subsequent
  post-game claim reads `claim.ethValueOwed == 0` (:823) and returns false (single) / skips (batch). The
  slot is cleared atomically with the release in the same tx. ✔
- **submit-vs-claim asymmetry:** submit IS gated (`BurnsBlockedBeforeDailyRng` :991, and the liveness/
  swept guards), the claim side is NOT — but the claim side is safe-by-construction because (i) the
  redemption reserve is segregated out of the game (drain can't touch it), (ii) `reserved = claimablePool`
  covers any live credit the claim pushes in, and (iii) the single `gameOver()` snapshot + atomic
  slot-delete prevent a live/post-game double-settle.
- **`claimRedemptionMany` batch:** caches `isGameOver` once (:791); the loop body
  (`_claimRedemptionFor`) has no untrusted player ETH hook that could flip `gameOver` mid-batch (credits
  ride claimable, no ETH pushed at the player in the live path; the keeper bounty is BURNIE-only). ✔

**SETTLING BOUND:** EVM tx atomicity + redemption-reserve segregation (drain `totalFunds` excludes it,
:82-84) + `reserved = claimablePool` + atomic release/slot-delete. No interleaving strands or
double-credits. **VERDICT: REFUTED (claim side safe-by-construction).**

### SOLV-06 — CEI / yield-surplus reentrancy (DEDICATED §6 prime, V62-03 class)

**PROPERTY:** every changed ETH/stETH payout leg debits state BEFORE the untrusted external call, and a
reentrant `distributeYieldSurplus` cannot read in-flight stETH as unreserved backing.
**ATTACK:** reenter `distributeYieldSurplus` from a player's ETH-receive hook during a payout while stETH
is still held but `claimablePool` is already debited → over-distribute the in-flight stETH as yield.

- **claimWinnings** (`DegenerusGame.sol:1247-1254`): `_debitClaimableAndAfking` + `claimablePool -= payout`
  (:1247-1248) BEFORE `_payoutWithStethFallback`/`_payoutWithEthFallback`. ✔
- **_payoutWithStethFallback** (:1888-1915, the `53cd25cf` reorder): moves the stETH leg out FIRST
  (:1902-1907, `_transferSteth` hands no control to `to`), untrusted ETH `.call` LAST (:1912-1914). A
  reentrant `distributeYieldSurplus` mid-`.call` sees `totalBal = balance + stETH` already reduced by the
  stETH transfer AND `claimablePool` already debited — so `totalBal − obligations` cannot count the
  in-flight stETH as surplus. The comment at :1891-1894 states exactly this. ✔
- **distributeYieldSurplus obligations** (`DegenerusGameJackpotModule.sol:688-700`): sum =
  currentPrizePool + nextPool + claimablePool + futurePool + yieldAccumulator + pendingNext + pendingFuture
  — ALL live obligations, read fresh. `if (totalBal <= obligations) return` (:702) → only the strict
  excess is distributed. Reading claimablePool fresh after a prior debit means a reentrant call sees the
  debited (lower) claimablePool but ALSO the reduced totalBal (stETH already out) — nets safe. ✔
- **pullRedemptionReserve** (:1582-1585): `_debitClaimable` + `claimablePool -= amount` BEFORE the
  `call{value:amount}` to sDGNRS — CEI. ✔
- **sDGNRS _payEth** (`StakedDegenerusStonk.sol:1108-1115`): stETH first, untrusted ETH `.call` LAST
  (the `claimRedemption` already decremented `_pendingRedemptionEthValue` :854, so a reentrant burn/claim
  in the player's ETH hook would otherwise read the in-flight stETH as free backing — the reorder
  prevents it, comment :1108-1110). ✔
- **dust-forfeit ETH send:** routed through `creditRedemptionDirect` (no ETH pushed at an untrusted
  player; the recipient is `address(this)` = sDGNRS, and the GAME pulls stETH then credits — no external
  call to an untrusted address). ✔
- **New redemption credit legs** (`creditRedemptionDirect`, `resolveRedemptionLootbox`): pull value in
  (stETH transferFrom) BEFORE `_creditClaimable`/pool write — value-in-before-credit, and the only
  external interaction is the stETH `transferFrom` from sDGNRS (an authorized, non-reentrant-on-game
  ERC20), not an arbitrary callee. No new reentrancy surface reopened. ✔

The 10/10 branch-proofs in `RedemptionStethFallback.t.sol` EXERCISE the V62-03 class on these legs;
this independent trace confirms every changed leg carries the reorder.
**SETTLING BOUND:** state debited before every external call; stETH out before the untrusted ETH `.call`
on all 4 payout helpers; obligations sum reads all live pools fresh. **VERDICT: REFUTED (V62-03 class
closed on the spine; no new leg reopens it).**

### SOLV-07 — JackpotModule delta-fold completeness + the whalePassCost divergence (PRIORITY)

**PROPERTY:** the manual delta-fold credits/deletes no pool twice; specifically the solo whale-pass split
single-counts `whalePassCost` (the gemini-vs-codex divergence).
**ATTACK:** find a `_creditClaimable` not folded into a `claimablePool +=`, or `whalePassCost` added to
TWO obligations both later paid.

**Frozen line-pin (resolving the cross-model cite mismatch).** `_processSoloBucketWinner` lives at
`DegenerusGameJackpotModule.sol:1246-1281` (gemini's ~1284 and codex's @1265-1275 both point inside this
function; the prompt's @1247 is the function header). `payDailyJackpot` lives at `:291-...`, with the
final-day fold at `:442-452`. I read both in full.

**`_processSoloBucketWinner` (:1246-1281), wei-level:**
```
quarterAmount   = perWinner >> 2                       (:1261)
whalePassCount  = quarterAmount / HALF_WHALE_PASS_PRICE (:1262)
if whalePassCount != 0:
    whalePassCost = whalePassCount * HALF_WHALE_PASS_PRICE (:1266)
    ethAmount     = perWinner - whalePassCost             (:1267)
    _creditClaimable(winner, ethAmount)                  (:1268)  ← ETH portion only
    claimableDelta = ethAmount                           (:1269)  ← folded to claimablePool
    ethPaid        = ethAmount                           (:1270)
    whalePassClaims[winner] += whalePassCount            (:1273)  ← non-ETH claim (tickets at redeem)
    _addFuturePrizePool(whalePassCost)                   (:1274)  ← ONE add to futurePrizePool
    whalePassSpent = whalePassCost                       (:1276)
else:
    _creditClaimable(winner, perWinner); claimableDelta = perWinner; ethPaid = perWinner (:1278-1280)
```
So at this function: claimablePool gets ONLY `ethAmount` (= perWinner − whalePassCost); futurePrizePool
gets `whalePassCost` exactly ONCE; `whalePassClaims` records the pass (redeemed for TICKETS via
`claimWhalePass` → `_queueTicketRange`, `DegenerusGameWhaleModule.sol:991-1007` — NO claimablePool credit,
NO ETH push). The whale pass is a non-ETH obligation; `whalePassCost` funds future ticket backing.

**Now the gemini double-credit claim — does `payDailyJackpot`'s final-day fold re-add `whalePassCost`?**
The pivotal question: does `paidDailyEth` (the value `_processDailyEth` returns) INCLUDE or EXCLUDE the
`whalePassCost`?

Trace the return chain:
- `_processDailyEth` accumulates `paidEth += paidDelta` per bucket (`:1110`, the loop at src+1099..),
  and separately `liabilityDelta += claimDelta` → one `claimablePool += liabilityDelta` (:1117-1120).
  `paidEth` and the claimable fold are DISTINCT accumulators.
- `paidDelta` for the solo bucket comes from `_handleSoloBucketWinner` (:1183-1216):
  `paidDelta += paid` (the ETH portion, :1209-1210) **AND** `if (wpSpent != 0) paidDelta += wpSpent`
  (:1214-1215). **So `paidDelta` — and therefore `paidDailyEth` — INCLUDES the whale-pass cost.**
- Back in `payDailyJackpot` final-day fold (`:442-449`):
  `unpaidDailyEth = dailyEthBudget − paidDailyEth` (:443). Because `paidDailyEth` already counts the
  `whalePassCost` (it was "paid" — converted to a pass + routed to futurePrizePool), the
  `unpaidDailyEth` residual EXCLUDES `whalePassCost`. The fold adds only the genuinely-unspent budget to
  futurePrizePool (:448). `whalePassCost` is therefore added to futurePrizePool EXACTLY ONCE (at :1274).
- **currentPrizePool debit:** final day `_setCurrentPrizePool(curPool − dailyEthBudget)` (:446) — debits
  the FULL budget (not just paidDailyEth), so no `whalePassCost` share is left stranded in
  currentPrizePool. Non-final day `_setCurrentPrizePool(curPool − paidDailyEth)` (:451) — debits
  `paidDailyEth`, which (as established) INCLUDES `whalePassCost`, so the whale-pass share IS removed from
  currentPrizePool on non-final days too. Gemini's "under-debit of currentPrizePool" premise (that
  `paidDailyEth` is "only the ETH portion") is FALSE at frozen source.

**Adjudication of the divergence:** gemini's double-credit relied on the premise that `paidDailyEth`
counts ONLY the ETH portion (excluding `whalePassCost`). At `a8b702a7`, `_handleSoloBucketWinner:1214-1215`
adds `wpSpent` into `paidDelta`, so `paidDailyEth` DOES include `whalePassCost`. The final-day
`unpaidDailyEth = budget − paidDailyEth` therefore does NOT re-add it, and the non-final-day
currentPrizePool debit DOES remove it. **No double-credit; no phantom inflation.** Codex's trace
(single-count: only ETH → claimableDelta, pass cost → futurePrizePool once) is CORRECT.

**SKEPTIC DUAL-GATE (run before NOT-elevating, per the divergence protocol):**
- *Structural-protection check:* even hypothetically — IF `whalePassCost` were folded twice into
  futurePrizePool, it would inflate a POOL obligation, NOT the `claimablePool` solvency identity I2
  (whale-pass value is outside I2). And `distributeYieldSurplus` includes `futurePrizePool` in its
  obligations sum (:691), so an inflated futurePrizePool would only REDUCE the computed yield surplus
  (conservative — fewer funds distributed), never cause an underbacked PAYOUT. The "insolvency over time"
  framing requires pool obligations to exceed BALANCE and both be paid out; futurePrizePool is paid only
  via subsequent jackpot/ticket cycles bounded by available balance, not an unconditional transfer.
- *3-condition EV/reachability lens:* (1) reachable? The double-credit is NOT present in code (paidDailyEth
  includes wpSpent) — fails condition (1). (2) profitable? n/a. (3) repeatable? n/a.
- *Gate result:* fails reachability condition (1). Not a finding. (Even the hypothetical would be a
  conservative pool over-reservation, not an underbacked payout — sub-HIGH by the structural check.)

**Delta-fold completeness (SOLV-07 second half):** `_addClaimableEth` was removed (F1); every former call
site now `_creditClaimable` directly + accumulates into `claimableDelta`/`liabilityDelta`, folded once per
path (daily :1117-1120, yield :707-713). `_payNormalBucket` (:1229) folds `perWinner` into
`totalLiability` → `claimDelta`. No path leaves a `_creditClaimable` outside a fold; no pool credited or
deleted twice.
**SETTLING BOUND:** `paidDailyEth` includes `wpSpent` (:1214-1215) ⟹ `unpaidDailyEth` excludes
`whalePassCost` ⟹ futurePrizePool += whalePassCost exactly once (:1274); claimablePool += ETH portion
only; whale pass is a non-ETH tickets claim. **VERDICT: REFUTED — single-counted. The gemini HIGH lead
is NOT confirmed at frozen source (its premise that `paidDailyEth` excludes whalePassCost is false).**

### FC-390-03 — permissionless decimator/redemption claim + gameOver/freeze edge

**PROPERTY:** the batch caches `over`/`frozen` once; no path resolves a claim into claimable that is then
forfeited; no mid-batch boundary flip splits a batch inconsistently.
**ATTACK:** trigger a victim's claim during a live game right as gameOver latches; or flip
`prizePoolFrozen`/`gameOver` mid-batch.

- `claimDecimatorJackpot(address player, uint24 lvl)` (`DegenerusGameDecimatorModule.sol:293-317`) is
  PERMISSIONLESS; "all value credits to `player` (the winner), never the caller"; "Resolution-into-
  claimable only (no ETH leaves here)" (:294-297). The player withdraws via the access-gated
  claimWinnings — so a permissionless trigger can NEVER push value to itself or strand it.
- Reverts on `prizePoolFrozen` (:298). The batch (:325-371) caches `packedOffsets`, `totalBurn`, `over`
  ONCE (:338-341) with the explicit invariant comment (:335-337): the round is written exactly once
  (runDecimatorJackpot idempotent per level) and gameOver only flips in game-over resolution — none of
  the claim effects below can change them. A claim effect (`_claimDecimatorJackpotFor`) credits claimable;
  it cannot flip gameOver or prizePoolFrozen (those flip only in the advance/gameover path, a SEPARATE
  tx). So no mid-batch boundary split. ✔
- "Resolved into claimable that is then forfeited" edge: in a LIVE game, a resolved claim credits the
  player's claimable which they withdraw normally (not forfeited). Post-gameover the live-credited
  claimable is subject to the final sweep after 30 days — but that's the documented gameover forfeiture
  policy for ALL unclaimed balances, applied uniformly, and the comment at StakedDegenerusStonk.sol:768
  notes the post-gameOver path uses direct PUSH precisely to avoid a claimable that would forfeit. The
  decimator post-game branch (`over` cached) credits from the already-reserved pool (council :401-404). ✔
- The keeper bounty (`creditFlip`, :364-370) is BURNIE-only — no ETH/stETH spine impact.

**SETTLING BOUND:** resolution-into-claimable only (no caller value path); batch caches over/frozen once
and claim effects can't flip them; permissionless trigger credits the winner not the caller.
**VERDICT: REFUTED (cross-ref 393 owns the forced-LEVEL-timing magnitude half FC-393-01).**

### FC-390-04 — burnEth claim-trigger simplification (`claimValue > combined`)

**PROPERTY:** dropping `&& claimable != 0` cannot trigger a wasted `claimWinnings(vault)` for a 0-net
amount at the edge `amount == supplyBefore`.
**ATTACK:** last DGVE burn (`amount == supplyBefore`) with `claimable == 0` (sentinel-only) yielding
`claimValue > combined`.

`DegenerusVault.sol:749-766`: `reserve = combined + claimable` (:756);
`claimValue = reserve*amount/supplyBefore` (:757). When `amount ≤ supplyBefore`,
`claimValue ≤ reserve = combined + claimable`. So `claimValue > combined ⟹ claimable > 0` (the proof
comment :759-761). At `amount == supplyBefore`: `claimValue == reserve == combined + claimable`, which
exceeds `combined` iff `claimable > 0`. `_netClaimableWinnings()` (:754) returns the 1-wei-sentinel-netted
claimable (dust → 0), so a sentinel-only state reads `claimable == 0` → `claimValue == combined` → the
guard at :762 is false → no wasted `claimWinnings`. The dropped conjunct is genuinely implied.
**SETTLING BOUND:** `claimValue ≤ combined + claimable` for accepted amounts; equality at the last-burn
edge requires `claimable > 0`. **VERDICT: REFUTED / MONITOR (worst case was only a wasted call; proven
unreachable).**

### FC-390-05 — gameDegeneretteBet overpay guard relocated game-side

**PROPERTY:** the game-side guard matches the removed vault formula.
`DegenerusGameDegeneretteModule.sol:535` `totalBet = amountPerTicket * ticketCount`; `:596`
`if (ethPaid > totalBet) revert InvalidBet()` (and `:597-598` settles shortfall from claimable). Identical
to the removed vault `value > amountPerTicket*ticketCount` cap. No value-leak; vault forwards combined
value (council :578-584). **VERDICT: INFO / VERIFIED (guard present + identical).**

### FC-390-06 — keeper-bounty creditFlip issuance bounded

**PROPERTY:** issuance is bounded so a keeper cannot mint unbounded BURNIE claim-value.
`claimRedemptionMany` pays per box ACTUALLY settled (`settled` counted, empty slots skipped,
StakedDegenerusStonk.sol:809-814); each (player,day) slot requires a real burn with the per-(wallet,day)
160-ETH base cap (:1081) and per-day 50% supply cap (:1012). `claimDecimatorJackpotMany` pays per real
claimed entry (`DegenerusGameDecimatorModule.sol:364-370`), one entry per real burn. BURNIE is OFF the
direct ETH/stETH spine; the downstream-dilution assessment is owned by ACCESS-02/393. The issuance bound
holds: bounded by the number of real burns/redemptions, each capped. **VERDICT: REFUTED (issuance
bounded); cross-ref 393/ACCESS-02 for downstream dilution.**

### FC-390-07 — vault deposit() removal completeness

**PROPERTY:** no remaining game-side `vault.deposit(...)` call (dead/reverting); over-mint reverts in
vaultMintTo against the live allowance.
`grep "vault.deposit\|.deposit(" contracts/` → EMPTY (no caller). `vaultMintTo` checks the live allowance
before minting (`BurnieCoin.sol:542-549`, council-cited) so `burnCoin`'s `remaining` over-mint reverts.
The vault now receives ETH via `receive()` + game claimable credits, stETH via direct ERC20 transfers,
BURNIE via mint-allowance — no game→vault stETH-pull path remains. **VERDICT: INFO / REFUTED (removal
complete, no dead caller).**

### FC-389-02 / FC-389-08 (inherited) — uint96/uint128 narrowing solvency-conservation half

Folded into SOLV-02 above. `_pendingRedemptionEthValue` (uint96) real-ETH bounded (per-wallet/day cap ×
175% ≪ uint96); `poolBalances`/`_totalSupply` (uint128) supply-bounded ≪ uint128; every narrowing on a
CHECKED expression (submit :1066, resolve :745, claim :854). No path inflates segregated ETH beyond
width → no backing understatement. **VERDICT: REFUTED (cross-ref 389 narrowing-equivalence half already
REFUTED; solvency-conservation half REFUTED here).**

### FC-392-08 (inherited) — redemption ETH-spin pool RMW + recirc vs CEI (solvency half)

**PROPERTY:** the ETH-spin pool writes + dust-forfeit + `_pendingRedemptionEthValue` release reconcile
exactly; the recirc box cap RMW can't be raced across chunks.
`resolveRedemptionLootbox` credits the pool by `amount` BEFORE chunk resolution (:945-947), pulling the
stETH remainder in first (:932-936). `_resolveRedemptionChunk` (:965) resolves in ≤5-ETH chunks with a
freeze-safe seed (no live day). The ETH-spin (`DegenerusGameDegeneretteModule.sol:1435-1463`) flushes
THIS spin's pool/claimable writes BEFORE recirc (`:1439-1447` — `_addClaimableEth` then `_setFuturePrizePool`/
`_setPendingPools`), so recirc reads fresh storage; recirc disables the ETH-spin cascade
(`allowEthSpin=false`, :1453). Each chunk is sequential within one delegatecall frame (same Game storage
context) — no cross-chunk race on the cap RMW (writes persist between chunks via storage, not a stale
cached word). The `_pendingRedemptionEthValue` release (:854) equals total leg movement (SOLV-03); the
ETH-spin pool RMW operates on futurePrizePool (a separate obligation), reconciled by the flush-before-
recirc ordering. **VERDICT: REFUTED (solvency/CEI half; the ECON EV half is owned by 392).**

### FC-393-02 (inherited) — forfeit-to-self timing

A keeper choosing WHICH redemptions to settle biases only the TIMING of benign backing accrual: the
per-claim split (ethDirect/lootboxEth/forfeitEth) is deterministic from the fixed `roll`
(`redemptionPeriods[day]`, :772) + the player's owed value (`claim.ethValueOwed`), with NO per-victim
value extraction (all value credits to the winner/sDGNRS-backing, never the caller). The forfeit raises
backing for ALL remaining holders uniformly (:842). **VERDICT: INFO / REFUTED (timing-only, non-
extractive; cross-ref 393).**

### FC-393-03 (inherited) — partial-balance redemption-leg solvency under same-block bursts

**PROPERTY:** under many partial-balance live claims in ONE block, segregation accounting
(`_pendingRedemptionEthValue` release == total leg movement) never strands ETH or under-pulls stETH.
**ATTACK:** sequence N claims in one block, each draining `address(this).balance` so later legs send
`min(bal, legAmount)` ETH and pull the rest as stETH; check the MAX(175%) reservation always covers.

Each leg recomputes `bal = address(this).balance` fresh (:880/:888/:898) and sends `min(bal, legAmount)`,
the GAME pulling `legAmount − sent` as stETH (reverts if short). Across a burst: the SUM of all legs over
all claims = Σ totalRolledEth = Σ released `_pendingRedemptionEthValue`. The MAX reservation held in
sDGNRS (ETH+stETH ≥ Σ MAX ≥ Σ rolled) covers the total; as ETH drains, later legs simply shift to the
stETH leg of the SAME held reservation (the stETH transferFrom draws on sDGNRS's stETH custody that the
reservation left in place). No ETH stranded (each leg sends all available ETH up to its amount, remainder
pulled as stETH); no stETH under-pull (transferFrom reverts fail-closed if insufficient). The
per-claim release (:854) always equals that claim's total leg movement. **VERDICT: REFUTED (segregation
holds under same-block bursts; solvency half — ACCESS half coordinated with 393).**

---

## C. Council fold (NET 1 — read AFTER the independent pass)

Read `390-01-COUNCIL-NET.md` + `council/solv.gemini.txt` + `council/solv.codex.txt` only after the above.

| Item | Council (NET 1) | NET 2 (this doc) | Convergent? |
|------|-----------------|------------------|-------------|
| SOLV-01..03 | both SOUND | REFUTED | ✔ convergent |
| SOLV-04 / FC-390-02 | both SOUND (value-in-before-credit) | REFUTED (dedicated backing proof) | ✔ convergent |
| SOLV-05 / FC-390-01 | both SOUND (tx-atomicity) | REFUTED (dedicated multi-tx (a)(b)(c)) | ✔ convergent |
| SOLV-06 | both SOUND (stETH-before-ETH) | REFUTED (dedicated CEI trace, 4 legs) | ✔ convergent |
| **SOLV-07 whalePassCost** | **gemini HIGH lead vs codex SOUND (DIVERGENT)** | **REFUTED — single-counted; gemini premise false at source** | resolves to codex SOUND |
| Decimator pre-reservation slack (codex caveat, INFO) | codex: over-reservation, conservative | confirmed conservative-only (see note) | ✔ convergent |
| FC-390-03 | both SOUND (cache once) | REFUTED | ✔ convergent |
| FC-390-04 | codex SOUND (equality not `>`) | REFUTED/MONITOR | ✔ convergent |
| FC-390-05 | both SOUND (guard identical) | INFO/VERIFIED | ✔ convergent |
| FC-390-06 | codex SOUND (bounded + sub-gas) | REFUTED (bounded) | ✔ convergent |
| FC-390-07 | codex SOUND (no caller) | INFO/REFUTED | ✔ convergent |
| FC-389-02/-08 | narrowings not reachable | REFUTED | ✔ convergent |
| FC-392-08 | codex SOUND (flush-before-recirc) | REFUTED (solvency half) | ✔ convergent |
| FC-393-02 | codex SOUND (non-extractive) | INFO/REFUTED | ✔ convergent |
| FC-393-03 | (under SOLV-04 partial-balance) | REFUTED | ✔ convergent |

**SOLV-07 divergence resolution (the slice's single material cross-model split):** the council DIVERGED —
gemini flagged a HIGH `whalePassCost` double-credit, codex refuted it as single-counted. NET 2's
independent wei-level trace of `_processSoloBucketWinner` (:1246-1281), `_handleSoloBucketWinner`
(:1183-1216, where `paidDelta += wpSpent` at :1214-1215), and `payDailyJackpot`'s final-day fold
(:442-452) shows gemini's load-bearing premise — that `paidDailyEth` counts ONLY the ETH portion — is
FALSE at frozen source. `paidDailyEth` INCLUDES `whalePassCost`, so `unpaidDailyEth = budget −
paidDailyEth` excludes it and the non-final-day `currentPrizePool -= paidDailyEth` removes it. The skeptic
dual-gate fails reachability condition (1). **NET 2 sides with codex: SOLV-07 single-counted, REFUTED.**
The gemini lead is NOT confirmed (and even hypothetically would be a conservative pool over-reservation
outside the claimablePool identity, not an underbacked payout — sub-HIGH on the structural check).

**Decimator pre-reservation slack (codex caveat):** confirmed conservative-only. The full decimator
`poolWei` is moved into `claimablePool` at RESOLUTION (DegenerusGameStorage.sol:356-366 documented
exception); at CLAIM the ETH half stays, the lootbox half migrates to futurePrizePool. This is an
OVER-reservation of backing (more held than strictly owed before winners are credited), not an
underbacked path, and is DISTINCT from the SOLV-07 daily-jackpot fold (different pool, different timing).
No interaction with the SOLV-07 lead.

---

## D. Test-coverage routing note (EthSolvency redemption-leg gap, from 388-02 #5)

`EthSolvency.inv.t.sol` EXERCISES the game-side claimablePool identity but its action set does NOT include
the redemption credit legs (`creditRedemptionDirect` / `resolveRedemptionLootbox` / the dust-forfeit leg).
`RedemptionStethFallback.t.sol` (10/10) + `RedemptionAccounting.t.sol` carry the redemption coverage as
targeted tests, but the always-on invariant net does not assert the I2 identity ACROSS a redemption
credit. **Routed test-hardening note (NOT a contract change):** a later test phase could add a redemption
action (live claim → creditRedemptionDirect) to the EthSolvency invariant handler so the always-on net
covers the redemption credit legs too. This is an oracle-completeness item, not a contract defect — every
redemption leg's solvency is proven above by trace + the EXERCISED targeted tests. The superseded legacy
`RedemptionInvariants` 7-INV green was NOT relied on anywhere in this net.

---

## E. Provisional-verdict rollup (NET 2)

| Item | Provisional verdict (NET 2) |
|------|------------------------------|
| SOLV-01 | REFUTED (identity pairing complete) |
| SOLV-02 | REFUTED (backing read excludes pending; widths bounded) |
| SOLV-03 | REFUTED (legs sum = rolled = release in every branch) |
| SOLV-04 / FC-390-02 | REFUTED (dust-forfeit fully backed; value-in-before-credit; fail-closed) |
| SOLV-05 / FC-390-01 | REFUTED (claim side safe-by-construction; reserve segregated out of drain) |
| SOLV-06 | REFUTED (CEI on all 4 payout legs; V62-03 class closed) |
| SOLV-07 | REFUTED (whalePassCost single-counted; gemini HIGH premise false; skeptic-gate fails reachability) |
| FC-390-03 | REFUTED (resolution-into-claimable only; cache-once batch) |
| FC-390-04 | REFUTED / MONITOR (wasted-call edge unreachable) |
| FC-390-05 | INFO / VERIFIED (guard present + identical) |
| FC-390-06 | REFUTED (issuance bounded; dilution → 393) |
| FC-390-07 | INFO / REFUTED (removal complete, no dead caller) |
| FC-389-02 | REFUTED (solvency-conservation half) |
| FC-389-08 | REFUTED (solvency-conservation half) |
| FC-392-08 | REFUTED (solvency/CEI half; ECON half → 392) |
| FC-393-02 | INFO / REFUTED (non-extractive timing) |
| FC-393-03 | REFUTED (partial-balance burst segregation holds) |

**0 CONFIRMED findings in NET 2.** The single material cross-model divergence (SOLV-07) resolves to
REFUTED (single-counted) on independent wei-level trace. Subject byte-frozen throughout
(`git diff a8b702a7 -- contracts/` EMPTY).
