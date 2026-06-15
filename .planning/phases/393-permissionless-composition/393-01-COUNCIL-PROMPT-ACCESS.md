# Council Sweep 393-01 — PERMISSIONLESS-COMPOSITION slice (ACCESS-01..05)

You are an external auditor on a cross-model council reviewing the **Degenerus Protocol** before a
Code4rena engagement. Read the EXACT frozen source at `a8b702a7` via
`git show a8b702a7:contracts/<File>.sol` (ignore the working tree — it has docs-only commits on top of
the frozen subject). Be concrete and reachable: a finding needs a real ordered call sequence (a multi-tx
trigger, a same-block burst of claims, or an observe-then-retrigger sequence — wherever the ordering
matters) and a named state variable with a `file:line` at `a8b702a7`. No speculative gaps.

This slice reviews the **new and widened PERMISSIONLESS / KEEPER entrypoints** of the post-v62 change set:
the permissionless `claimDecimatorJackpot(address,uint24)` (formerly self-only `claimDecimatorJackpot(uint24)`),
the new `claimDecimatorJackpotMany(address[],uint24)`, the permissionless-during-live
`claimRedemption(address,uint24)` + the new `claimRedemptionMany(address[],uint24)`, the new
`claimCoinflipCarry(address,uint256)`; the two keeper box-bounties paid on the two batch entrypoints; the
forced-claim-TIMING surface a third party can now impose on a winner; the partial-balance redemption-leg
burst solvency; the freeze/rngLocked/liveness/gameOver gate intactness on every new/widened entrypoint; the
ETH/stETH reentrancy across the legs; and the widened coinflip claim-loop gas. We believe these properties
hold across the change set — **every permissionless claim credits ONLY the beneficiary (never `msg.sender`),
each keeper bounty is net-NEGATIVE vs real prevailing gas AND structurally un-manufacturable, the forced
claim-timing is inert (frozen seeds bound the randomness; the timing class is by-design), the partial-balance
leg accounting never strands ETH or under-pulls stETH under same-block bursts, and the freeze / rngLocked /
liveness / gameOver gates plus the ETH/stETH CEI ordering are intact on every new/widened entrypoint.**
**Your job is to find where one of these beliefs breaks.**

## Threat priority (USER-locked for this slice)

DOMINANT = RNG/freeze (audited in the 391 RNG slice — the frozen-seed/word-unknown-at-commitment invariant
over the decimator-claim and redemption-lootbox seeds was attested there; do NOT re-audit the freeze window
here, only confirm the gate is PRESENT on each new entrypoint). HIGH = gas-DoS only in the `advanceGame`
chain (16,777,216 gas = brick) — these claim loops are CALLER-PAID and OFF the `advanceGame` chain, so a
widened claim loop is INFO unless you can force a many-hundred-day cold-SLOAD walk into the `advanceGame`
chain specifically. SPINE = solvency. **LOW/confirmatory = access-control / reentrancy / MEV** — this is
the LOW/confirmatory threat class for this slice as a whole.

**BUT the two SUBSTANTIVE items in this slice weigh higher than the LOW base class:**
- **ACCESS-02 (keeper-bounty economics vs real gas)** — a real faucet (a net-positive-at-realistic-gas
  bounty, or a manufacturable bounty-eligible work item) would be a value-bearing finding.
- **ACCESS-04 (partial-balance redemption-leg burst solvency)** — this is solvency-ADJACENT (the leg
  accounting backs real ETH/stETH redemption value), so a stranded-ETH / under-pulled-stETH break under a
  same-block burst weighs at the SPINE level, not the LOW base.

A real grief (a forced ETH push at / forced credit to a victim), a real faucet (a manufacturable or
net-positive bounty), a real steer (value routed to the caller, or an outcome a caller can bias), or a
burst-solvency strand therefore weighs higher than the LOW base class. Confirmatory access-control /
reentrancy checks are LOW.

## Trust-boundary & doctrine framing (so you do not waste passes)

**The thin-dispatcher fact.** `DegenerusGame.sol` is a selector-matched delegatecall dispatcher: every
external function is an explicit stub of the form `(...).delegatecall(msg.data)` into the owning module
(e.g. `claimDecimatorJackpot(address,uint24)` at `DegenerusGame.sol:808`, `claimDecimatorJackpotMany` at
`:832`). `delegatecall` preserves `msg.sender` AND `address(this)`, so module-side `msg.sender` is the
EXTERNAL caller and module-side external calls (e.g. `coinflip.creditFlip`) originate from the GAME
address. This means the module-side access gates (`msg.sender != COIN`, `msg.sender != SDGNRS`, etc.) and
the `onlyFlipCreditors` / `onlyGame` checks on the callees remain correct under the dispatcher. **Confirm
no stub mis-routes a permissionless entrypoint into a gated one (or a gated entrypoint into a permissionless
path) — and that a delegatecall does not let a permissionless caller inherit the GAME address's authority
on a callee that should reject the external caller.**

**The beneficiary-only doctrine.** A permissionless caller must credit ONLY the beneficiary. Every
permissionless claim (`claimDecimatorJackpot(player,…)`, `claimRedemption(player,…)`, their `Many` batches,
`claimCoinflipCarry(player,…)`) must forward value to `player` (or into the player's game-claimable /
lootbox), NEVER to `msg.sender`, and must NOT push ETH at a victim or force a credit a victim does not
want. A third-party trigger must hold no exclusive timing edge over the value. **Find any path that pushes a
forced credit / ETH at a victim, or routes value to the caller.**

**The keeper-bounty doctrine.** A keeper bounty must be net-NEGATIVE vs REAL prevailing gas (5/20/50+ gwei,
NOT the 0.5-gwei `AUTO_GAS_PRICE_REF` peg) AND structurally UN-MANUFACTURABLE (the bounty-eligible work item
must exist only because a real player burned — no Sybil can fabricate it). A bounty that is net-positive at
any realistic gas, or that can be manufactured, is a faucet.

**For EACH new/widened external entrypoint, enumerate:** (i) caller authorization (who gets the value), (ii)
the freeze / rngLocked / liveness / gameOver gate, (iii) the ETH/stETH reentrancy ordering, and (iv) what a
permissionless caller can grief / faucet / steer by choosing WHEN and WHAT to call.

## KNOWN BY-DESIGN (do NOT flag — out of scope for this slice)

- **Permissionless / lootbox claim/open TIMING is not a player edge** ([[lootbox-resolution-timing-by-design]])
  — the open is permissionless and economically-incentivized, and the seed is FROZEN at request, so do NOT
  flag day/level/wait-to-open steering as a freshness or fairness bug PER SE. The council's forced-timing
  job here is STRICTLY the MAGNITUDE question of ACCESS-03 / FC-393-01 (below) — whether the reward MAGNITUDE
  diverges between adjacent levels enough to make a forced resolution materially harmful — NOT the timing
  model itself.
- **Operator-approval IS the trust boundary** ([[open-e-operator-approval-trust-boundary]]) — do NOT model a
  "tricked into approving" actor. The `_resolvePlayer` self/operator-approved resolution and the
  BURNIE-funding operator overload are accepted by design.
- **An admin / protocol-address breaking its OWN game/position at genesis with no engaged community is a
  NON-finding** ([[genesis-admin-self-break-nonfinding]]) — do not model a genesis self-harm at
  `votingSupply()==0`.
- **The dust-lootbox-drop-to-claimable (<0.01 ETH half forfeited to sDGNRS's own claimable) is intended
  anti-dust-farm, NOT a bug** ([[redemption-dust-lootbox-drop-bydesign]]) — the drop itself is settled
  intent. The forfeit-to-self job (ACCESS-01 / FC-393-02) is STRICTLY whether a keeper can EXTRACT
  per-victim value by choosing which redemptions to settle, NOT the drop itself.
- **EV>100% RTP / positive-EV lootbox / positive-EV coinflip / RTP economics are NOT findings**
  ([[degenerette-wwxrp-rtp-by-design]], [[intended-game-mechanics-not-findings]]) — not the subject here.

## The thesis to BREAK (mapped to ACCESS-01..05)

We believe ALL of the following hold. Find a concrete counterexample to any one — or VERIFY SOUND with the
specific reason it holds.

- **(ACCESS-01) Every permissionless claim credits ONLY the beneficiary.** `claimDecimatorJackpot(player,…)`,
  `claimRedemption(player,…)`, their `Many` batches, and `claimCoinflipCarry(player,…)` all forward value to
  `player` (or into the player's game-claimable / lootbox), never to `msg.sender`, so a third-party trigger
  pushes no ETH at the player and holds no exclusive timing edge. Find any path that pushes a forced credit
  or ETH at a victim, or routes value to the caller.
- **(ACCESS-02) Both keeper box-bounties are net-NEGATIVE vs real prevailing gas AND un-manufacturable.** The
  bounty is `BOX_BOUNTY_ETH_TARGET = 15_000_000_000_000` wei (0.000015 ETH) of value per settled box,
  delivered as ILLIQUID BURNIE flip-credit (`creditFlip` → next-day stake that must survive a 50/50 flip ×0.5
  × the BURNIE→ETH peg discount), ~40x under-water at 20 gwei BEFORE the flip risk, and each settle-able box
  exists only because a real player BURNED. Find any way to fabricate bounty-eligible work or to make the
  bounty net-positive at any realistic gas.
- **(ACCESS-03) Forced claim-timing on the winner is INERT.** Frozen seeds bound the randomness and the
  timing class is by-design, so the ONLY question is whether any reward MAGNITUDE / target-level distribution
  diverges enough between ADJACENT levels (the live-level-dependent `_rollTargetLevel(level+1)` and the
  whale-pass start level) to make a forced resolution materially harmful to the winner.
- **(ACCESS-04) Partial-balance redemption-leg solvency holds under same-block bursts.** Each leg sends
  `min(address(this).balance, legAmount)` ETH and pulls the rest as stETH, and the MAX (175%) reservation
  guarantees ETH+stETH ≥ rolled across many one-block claims without stranding ETH or under-pulling stETH.
- **(ACCESS-05) The freeze / rngLocked / liveness / gameOver gates are intact on EVERY new/widened
  entrypoint, and reentrancy is closed across the ETH/stETH legs.** The decimator / redemption claims gate
  `prizePoolFrozen`; post-gameOver redemption is self-claim-only; `claimCoinflipCarry` gates `rngLocked`; the
  CEI ordering (slot delete + ledger debit before the untrusted `.call`; stETH-first / ETH-last; the
  `53cd25cf` `_payoutWithStethFallback` reorder closing V62-03) holds.

## Authoritative frozen line-cites (read the code via `git show a8b702a7:...`, do not trust the cite blindly)

- `contracts/modules/DegenerusGameDecimatorModule.sol`: permissionless
  `claimDecimatorJackpot(address player, uint24 lvl)` @293 (credits `player`, never the caller; gates
  `prizePoolFrozen` @298); `claimDecimatorJackpotMany(address[], uint24)` @325 (batch, skips claimed /
  non-winner entries with NO revert, caches `over` / `frozen` / offsets / `totalBurn` ONCE @338-341); shared
  core `_claimDecimatorJackpotFor` @385; the keeper bounty `BOX_BOUNTY_ETH_TARGET = 15_000_000_000_000` wei
  per settled box, paid `!gameOver && settled != 0` as `(settled * TARGET * PRICE_COIN_UNIT) /
  _mintPriceInContext()` BURNIE `creditFlip` to `msg.sender` @364-370; `_mintPriceInContext()` @376
  reproduces the Game's `mintPrice()` (`priceForLevel(jackpotPhaseFlag ? level : level+1)`); the forced-timing
  surface `_rollTargetLevel(level+1, frozenSeed)` + the whale-pass `_queueTicketRange(winner, level+1, …)`
  read the LIVE `level` at claim time @283-322; the frozen lootbox seed `round.rngWord` snapshot @277.
- `contracts/StakedDegenerusStonk.sol`: `claimRedemption(address player, uint24 day)` @771 (permissionless
  during a LIVE game; self-only post-gameOver — `isGameOver && player != msg.sender` reverts `Unauthorized`);
  `claimRedemptionMany(address[], uint24)` @787 (batch, skips empty / non-self-post-game, bounty mirror
  `BOX_BOUNTY_ETH_TARGET` `creditFlip` @803-814); the dust-lootbox drop <`MIN_REDEMPTION_LOOTBOX_ETH` (0.01
  ETH) FORFEITED to sDGNRS's own claimable @839-848 / @897-901; the partial-balance legs send
  `min(address(this).balance, legAmount)` ETH + GAME pulls the remainder as stETH @880 / @888 / @898; the
  `_pendingRedemptionEthValue` release; the lootbox seed `hash2(rngWord, player)` with `rngWord =
  rngWordForDay(day+1)` @878; the submit gate `_submitGamblingClaimFrom` requires `rngWordForDay(currentPeriod)
  != 0` (revert `BurnsBlockedBeforeDailyRng`) @991; the post-gameOver path deletes `pendingRedemptions` +
  lowers `_pendingRedemptionEthValue` BEFORE `_payEth` (`.call`) (CEI) @1098; the Game callees
  `resolveRedemptionLootbox` @926 (`msg.sender != SDGNRS` gate) + `creditRedemptionDirect` @1004
  (`msg.sender != SDGNRS` gate).
- `contracts/BurnieCoinflip.sol`: `claimCoinflipCarry(address player, uint256 amount)` @366 (`player =
  _resolvePlayer(player)` — self or operator-approved; mints to `player` not the caller; gates `rngLocked`
  @371; settles resolved days first, then pays from the SETTLED carry); the widened windows
  `COIN_CLAIM_DAYS` 90→365, `AUTO_REBUY_OFF_CLAIM_DAYS_MAX` 1095→1460; counters uint8→uint16 @136-138 (deep
  walk `uint32 remaining` safe 1460, shallow `uint16` safe 365); `onlyBurnieCoin` tightened to COIN only
  (SDGNRS dropped); `onlyFlipCreditors` = {GAME, QUESTS, AFFILIATE, ADMIN, SDGNRS}; `processCoinflipPayouts`
  (`onlyDegenerusGameContract`) sDGNRS auto-settle walks `deep=false` (bounded `windowDays` 365, ~1
  day/advance).
- `contracts/modules/DegenerusGame.sol`: the dispatcher stubs `claimDecimatorJackpot(address,uint24)` @808 +
  `claimDecimatorJackpotMany` @832; `_payoutWithStethFallback` @1888 reordered (`53cd25cf`) stETH-leg-out
  FIRST, ETH `.call` LAST (closes the V62-03 solvency-reentrancy); `distributeYieldSurplus` reachable only
  internally from `advanceGame` (`_distributeYieldSurplus`, `AdvanceModule:529/783`), no external stub,
  credits-only, only when `totalBal > obligations`.

## Already-adjudicated cross-ref halves (attack the ACCESS half CONSISTENTLY, do NOT re-derive)

The 388-392 sweeps already adjudicated the solvency / ECON halves of four leads that touch this surface.
State these as the consistency ANCHOR and attack ONLY the ACCESS half — do not re-derive the settled half:

- **FC-390-03 (mid-batch gameOver/frozen boundary) — solvency REFUTED at 390.** The batch caches `over` /
  `frozen` / offsets / `totalBurn` ONCE @338-341 so claim effects cannot flip the boundary mid-batch, and
  resolution credits into claimable only (all value to the winner). **Owned ACCESS half (here):** can ANY
  permissionless batch split inconsistently across the boundary, or resolve a claim into a claimable that the
  post-gameOver sweep then forfeits?
- **FC-390-06 (keeper-bounty `creditFlip` issuance bound) — solvency REFUTED at 390.** Issuance is bounded:
  one box per real claim, the `(wallet,day)` 160-ETH base cap + the 50%/day supply cap on the redemption
  side, the decimator per real claimed entry. **Owned ACCESS half (here):** the downstream BURNIE-dilution
  half of ACCESS-02 — can a keeper mint UNBOUNDED dilutive BURNIE claim-value that downstream dilutes the
  sDGNRS / vault ETH backing?
- **FC-392-08 (redemption ETH-spin pool RMW + recirc) — solvency/CEI REFUTED at 390** (flush-before-recirc,
  stETH-remainder pulled in before credit, chunks sequential in one frame) **+ ECON cap-RMW BY-DESIGN at 392**
  (recirc depth 1 `allowEthSpin=false`, monotonic cap). **Owned ACCESS half (here):** the permissionless
  cross-chunk / same-block RACE half — can the cap-RMW or the pool RMW be raced across chunks or across
  same-block claims by a permissionless caller?
- **FC-392-20 (widened claim-loop gas) — INFO at 392** (bounded, caller-paid, off the `advanceGame` chain).
  **Owned half (here as FC-393-04):** the FRESH worst-case under the new packed masked sub-word reads.

## Concrete break-targets

Charge **ACCESS-02** (keeper-bounty economics) and **ACCESS-04** (partial-balance burst solvency) HARD as
the two DEDICATED numbered prime items — they demand a REAL argument with the accounting traced, NOT a
hand-wave.

### 1. (PRIME — ACCESS-02, the keeper box-bounty / faucet target) Bounty economics vs REAL gas + un-manufacturability

Both bounties are `BOX_BOUNTY_ETH_TARGET = 15_000_000_000_000` wei (0.000015 ETH) of value per settled box,
paid `!gameOver && settled != 0` as `(settled * TARGET * PRICE_COIN_UNIT) / _mintPriceInContext()` BURNIE
flip-credit to `msg.sender` (`DecimatorModule:364-370`; `StakedDegenerusStonk:803-814`). **DO NOT use the
0.5-gwei `AUTO_GAS_PRICE_REF` peg.** Demand a REAL economic argument:

- **(i) Real-gas faucet test.** Cost the per-box settle (the ~30k-gas settle + the lootbox-resolve
  delegatecall it does for a LIVE winner) at REAL prevailing gas (5 / 20 / 50+ gwei) and confirm the
  0.000015-ETH reward is net-NEGATIVE BEFORE the 50% flip risk and the flip-credit illiquidity (`creditFlip`
  → `_addDailyFlip` next-day stake, must survive a 50/50 flip ×0.5, then the BURNIE→ETH peg discount ≈0.59)
  — so the realized LIQUID value is a small fraction of 0.000015 ETH while the gas is many multiples of it.
- **(ii) Un-manufacturability proof.** Each settle-able box exists only because a real player BURNED — the
  decimator bounty requires a real decimator-BURNIE burn; the redemption bounty requires a real sDGNRS
  gambling-burn — so a Sybil cannot fabricate bounty-eligible work. Couple this to FC-390-06 (the issuance is
  bounded: one box per real claim, the `(wallet,day)` 160-ETH base cap + the 50%/day supply cap on the
  redemption side, the decimator per real claimed entry) so a keeper cannot mint UNBOUNDED BURNIE claim-value
  that downstream dilutes the sDGNRS / vault ETH backing.
- **(iii) Bounty-size skew.** Confirm `_mintPriceInContext()` (@376) reproduces the Game's `mintPrice()`
  EXACTLY so the caller cannot SKEW the bounty size, and the ETH-value of the bounty is price-independent.

Find any way to fabricate bounty-eligible work, to make the bounty net-positive at any realistic gas, or to
mint unbounded dilutive BURNIE — OR state VERIFIED SOUND with the concrete real-gas + illiquidity +
un-manufacturability numbers. **A hand-wave ("illiquid so fine") is NOT acceptable — require the real-gas
accounting.**

### 2. (PRIME — ACCESS-04 / FC-393-03, the partial-balance burst-solvency target) Same-block multi-claim leg accounting

Each redemption leg sends `min(address(this).balance, legAmount)` ETH and pulls the rest as stETH
(`StakedDegenerusStonk` @880 / @888 / @898); the comment asserts the MAX (175%) reservation guarantees
ETH+stETH ≥ rolled. Demand a real same-block multi-claim leg-accounting argument: under an ADVERSARIAL
sequence of MANY partial-balance LIVE claims in ONE block (the permissionless `claimRedemptionMany` /
interleaved `claimRedemption` calls draining the contract ETH balance progressively), does the segregation
accounting hold — i.e. is Σ(legs over the burst) == Σ(rolled) == Σ(released `_pendingRedemptionEthValue`),
and does the MAX (175%) reservation (ETH+stETH ≥ Σ MAX ≥ Σ rolled) actually cover each leg so that an
ETH-balance drain merely SHIFTS the deficit to the stETH leg of the SAME held reservation — never stranding
ETH (left unreleased) or under-pulling stETH (GAME pulls less than the remainder)?

**Spell out the interleavings to try:**
- a claim that drains `address(this).balance` to near-zero so the NEXT claim's ETH leg clamps to ~0 and the
  entire roll must come from stETH;
- a claim whose stETH `transferFrom` would exceed the held reservation;
- many small partial-balance claims in one block whose cumulative ETH legs out-pace the contract balance.

Couple to the 390 FC-392-08 / FC-393-03 solvency-half adjudication (REFUTED at 390: each leg recomputes a
fresh `bal`, GAME pulls the remainder fail-closed reverting if short, Σ legs == Σ rolled == Σ released, the
MAX reservation covers) — attack the ACCESS half (the cross-chunk / same-block race + the cap-RMW raced
across chunks that the FC-392-08 permissionless-race half routed here) for consistency, and either confirm
the burst can't strand / under-pull OR surface a finding. **A hand-wave ("the reservation covers it") is NOT
acceptable — require the burst accounting traced.**

### 3. (ACCESS-03 / FC-393-01, LOW — the forced-timing MAGNITUDE question, NOT the timing model)

A third party can now FORCE a winner's live-game decimator claim to resolve at a `level` the winner did not
choose — `_rollTargetLevel(level+1, frozenSeed)` and the whale-pass `_queueTicketRange(winner, level+1, …)`
read the LIVE `level` at claim time (`DecimatorModule:283-322`). The frozen seed prevents win/loss steering
(DO NOT re-litigate that — timing is by-design). **The ONLY question:** does any reward MAGNITUDE /
target-level distribution diverge enough between ADJACENT levels to make a forced resolution MATERIALLY
harmful to the winner (e.g. a griefer settling just before an advance that shifts the target-level
distribution or the whale-pass start level)? Quantify the adjacent-level magnitude divergence and rule it
material or inert — with the concrete distribution reasoning, NOT a "timing is by-design so fine"
dismissal.

### 4. (ACCESS-01 / FC-393-02, INFO — forfeit-to-self timing, per-victim extraction?)

The dust lootbox (<0.01 ETH half) forfeits to sDGNRS's OWN claimable (`StakedDegenerusStonk:839-848 /
:897-901`), raising backing for ALL holders. A keeper choosing WHICH redemptions to settle could bias WHEN
forfeits land vs when full lootboxes resolve. **The dust-drop itself is by-design**
([[redemption-dust-lootbox-drop-bydesign]]) — the question is STRICTLY whether a keeper can EXTRACT
per-victim value. Confirm the per-claim split is DETERMINISTIC from the fixed roll + the player's own owed
value, so there is NO per-victim value extraction — only a benign timing of uniform backing accrual — OR
surface a finding.

### 5. (ACCESS-05, the gate + reentrancy intactness sweep across the new/widened entrypoints)

Confirm on EACH of `claimDecimatorJackpot` / `Many`, `claimRedemption` / `Many`, `claimCoinflipCarry`:
- **(i) Gate.** The freeze / rngLocked / liveness / gameOver gate is present and correct — the decimator +
  redemption claims revert on `prizePoolFrozen`; post-gameOver redemption is self-claim-only (`isGameOver &&
  player != msg.sender` reverts `Unauthorized`); `claimCoinflipCarry` gates `rngLocked`.
- **(ii) Reentrancy / CEI.** The post-gameOver `claimRedemption` deletes the `pendingRedemptions` slot +
  lowers `_pendingRedemptionEthValue` BEFORE the untrusted `_payEth` `.call`; `_payEth` sends stETH first
  then the ETH `.call` last; the Game's `_payoutWithStethFallback` @1888 reordered (`53cd25cf`)
  stETH-out-first / ETH-call-last closing V62-03.
- **(iii) Callee gates.** The Game-side callees `resolveRedemptionLootbox` (@926) + `creditRedemptionDirect`
  (@1004) gate `msg.sender != SDGNRS`, and `distributeYieldSurplus` is reachable only internally from
  `advanceGame` (no external stub, credits-only) — confirm it is not an independently exploitable
  permissionless lever.

Find any missing / widened gate or open reentrancy path across the legs, OR confirm intact. **Fold in
cross-ref FC-390-03** (LOW — the mid-batch gameOver/frozen boundary, solvency REFUTED at 390: the batch
caches `over` / `frozen` / offsets / `totalBurn` ONCE @338-341 so claim effects can't flip the boundary
mid-batch; confirm the ACCESS half — no permissionless batch can split inconsistently across the boundary).

### 6. (ACCESS-05 / FC-393-04 / cross-ref FC-392-20, INFO — the widened claim-loop gas worst-case)

The coinflip claim windows widened (`COIN_CLAIM_DAYS` 90→365, `AUTO_REBUY_OFF_CLAIM_DAYS_MAX` 1095→1460,
counters uint8→uint16) over the NEW packed storage (each day is now a masked sub-word read/write). The claims
are user-paid + OUT of the `advanceGame` chain; the `advanceGame`-chain sDGNRS auto-settle walks `deep=false`
(bounded `windowDays` 365, ~1 day/advance). FC-392-20 ruled this INFO at 392 (bounded, caller-paid, off the
chain) and routed the FRESH worst-case here. Confirm no realistic actor can force a many-hundred-day
cold-SLOAD walk into a GAS-SENSITIVE caller (the `advanceGame` chain specifically) under the new packed
masked sub-word layout — i.e. the worst-case 365/1460 loop is reachable only by a caller paying their OWN
gas, never bricking `advanceGame`. Confirm inert OR surface.

## Output (per item)

For each break-target AND each thesis point (ACCESS-01..05), state ONE of:
- **FINDING:** PROPERTY broken · reachable ordered CALL SEQUENCE (multi-tx / same-block burst /
  observe-then-retrigger — where the ordering matters) · STATE VAR + `file:line` at `a8b702a7` · SEVERITY
  (per the threat priority above — a real faucet or a burst-solvency strand weighs higher than the LOW base
  class) · WHY the existing authorization / gate / CEI / reservation protections do NOT stop it.
- **VERIFIED SOUND / IDENTICAL:** the property and the SPECIFIC reason it holds — cite the beneficiary
  credit, the gate, the CEI ordering, the reservation bound, or the un-manufacturability — so the
  adjudicator can confirm your reasoning.

Do NOT pre-state a verdict you have not traced to source. Read the frozen tree at `a8b702a7` via `git show`.
The council finds; the adjudicator (Claude) reconciles at 393-02.
