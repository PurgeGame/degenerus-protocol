# Council Sweep 392 — ENTROPY-AND-ECON: reward game-theory of the post-v62 rebalances (ECON-01..06)

You are an external auditor on a cross-model council reviewing the **Degenerus Protocol** before a
Code4rena engagement. Read the EXACT frozen source at `a8b702a7` via
`git show a8b702a7:contracts/<File>.sol` (ignore the working tree — it has docs-only commits on top).
Be concrete and reachable: a finding needs a real ordered call sequence (the repeatable cycle for a money
pump; the acquisition cost for the scarce whale pass; the multi-day grind for an unbounded-accrual claim)
and a named state variable with a `file:line` at `a8b702a7`. No speculative gaps.

This slice reviews the **reward game-theory** of the post-v62 reward rebalances — the EXPECTED-VALUE and
INCENTIVE structure, NOT the RNG-freshness of the words that drive them (that is the 391 slice, already on
record). We believe the reward economics are **sound** after the rebalances: every reward consumer
saturates BELOW its hard accrual ceiling; each documented redistribution is EV-neutral in code; the two
genuine EV changes match documented intent; no closed positive-EV money pump exists across the composed
surfaces; the scarce-asset whale half-pass stays near-unfarmable with a per-bracket supply of one; and the
now-uncapped/halved quest streak is rate-bounded and decay-gated. Your job is to find where that belief
breaks.

## Threat priority (USER-locked for this slice)

DOMINANT = RNG/freeze (the 391 slice — NOT this slice's job; do not re-audit freshness here). For the ECON
slice the highest-severity break is a **CLOSED POSITIVE-EV MONEY PUMP** — a repeatable cycle where realized
value-out exceeds value-in (this is HIGH; value is extractable in a loop). Next, a **SCARCE-ASSET SUPPLY
break** — an extra whale half-pass minted BEYOND the one-per-10-level-bracket cap, by any acquisition route
or race — is value-bearing. An **UNBOUNDED ACCRUAL grind** — any reward surface where a player input (the
now-uncapped quest streak included) pushes a downstream reward PAST its prior saturation ceiling — is
value-bearing. SPINE = solvency (the redemption-claim / ETH-pool reconciliation half is the 390 slice;
surface only the ECON-level value-extraction half here and cross-ref the solvency half to 390). HIGH =
gas-DoS only in the `advanceGame` chain (16,777,216 gas = brick). LOW/confirmatory = access-control /
reentrancy / MEV.

**A pure reward-magnitude or desirability complaint about a DOCUMENTED change is NOT a finding.** The
documented EV-multiplier lift and the recycle-bonus relaxation are intended; an "EV too high / RTP too
generous" observation about a documented number is out of scope. The finding bar is a BROKEN PROPERTY (a
money pump, a supply over-mint, an accrual past a hard cap, a coded value diverging from its documented
EV-neutral target), not a tuned magnitude.

## The design-intent anchor (VERIFY the claims — do NOT re-litigate the documented changes)

Per `.planning/PAPER-REWARD-CHANGES-BRIEF.md` (the canonical reward-change spec), the post-v62 rebalances
are documented and fall into two classes. Your job is to VERIFY the documented claims hold IN CODE — that
the arithmetic matches and the bound binds — NOT to argue whether the changes are desirable.

**Class A — EV-NEUTRAL REDISTRIBUTIONS (same expected value, different shape).** These are claimed
EV-neutral by construction; verify the coded value matches the claimed target:
- The lootbox reward-component split per roll (`roll % 20`): **tickets 40% / DGNRS 15% / WWXRP-spin 15% /
  BURNIE-flat 15% / BURNIE-spins×3 10% / ETH-spin 5%**. The three new spin outcomes (WWXRP-spin,
  BURNIE-spins, ETH-spin) STAKE the value they replace — the spin is claimed EV-equal to the flat award it
  supersedes.
- The ticket-roll budget **×11/9** (base 16,100 → 19,678 bps) so that despite tickets dropping 55%→45%
  (then 45%→40%), aggregate ticket ETH value is preserved (old 0.55×16,100 = 8,855; new 0.45×19,678 =
  8,855.1; the further 45→40% carve is the 5% ETH-spin staking the tickets it replaces).
- The far-future weighting: far-future share 10%→20% (near 90%→80%), with far rolls at **1.5×** budget and
  near at **0.875×** → 0.2×1.5 + 0.8×0.875 = **1.0** (claimed exactly EV-neutral).
- The variance tiers (chances 1/4/20/45/30%) converted from fixed multipliers to symmetric BPS ranges
  centered on the old per-tier value, drawn from the SAME variance roll (no extra entropy), overall
  variance EV preserved at **0.786×**.
- The BURNIE survival flip on the BURNIE-spins (double-or-nothing on one 50/50 coinflip before mint) is
  claimed EV-neutral (×2 at p=0.5).

**Class B — the TWO GENUINE EV CHANGES (BY-DESIGN — verify the documented numbers + the binding cap):**
- The **lootbox EV-multiplier lift**: floor 80%→**90%**, ceiling 135%→**145%**, score-to-ceiling
  25,500→**40,000** bps (neutral unchanged at 100% at score 6,000). Genuine RTP increase, gated by the
  per-(player,level) **10-ETH benefit cap** (`_applyEvMultiplierWithCap`). Verify the band IS 9000–14500
  bps with score-to-ceiling 40,000, AND the 10-ETH cap binds the total uplift regardless of box count.
- The **recycle-bonus relaxation**: the 10% BURNIE flip-credit kicker on recycled claimable now gates ONLY
  on `totalClaimableUsed >= priceWei*3` (≥3 whole tickets' worth), with the old `spentAllClaimable`
  drain-detection block deleted. Verify the gate IS ≥3-whole-ticket with the drain check removed, and that
  the bonus stays EV-neutral-or-negative (illiquid flip-credit that must survive a coinflip; the input is
  real already-won claimable spent on sub-100%-direct-EV tickets).

Everything else is pure reshaping — same money, better feel. Do NOT flag a documented Class-A redistribution
or a documented Class-B change as "too generous"; DO flag a coded value that DIVERGES from its documented
EV-neutral target (Class A) or from its documented number (Class B), or a cap that does NOT bind.

## Trust-boundary framing (so you do not waste passes)

`DegenerusGame.sol` + `contracts/modules/*.sol` all inherit the SAME `DegenerusGameStorage` base; the
reward consumers (lootbox EV multiplier, Degenerette/WWXRP ROI, decimator boost, the box-spin resolvers,
the recycle kicker, the affiliate roll) are `delegatecall` targets reading that one shared base. The
box-spin resolvers guard `address(this) != GAME` so they execute only inside a delegatecall from the Game.
`StakedDegenerusStonk` and `BurnieCoinflip` are standalone (regular CALL, own storage); they reach the
game's reward state through interface reads. The economics that matter for THIS slice are the EXPECTED-VALUE
arithmetic, the ACCRUAL bounds, and the SCARCE-SUPPLY flags — NOT cross-module layout aliasing (the 389
slice) and NOT RNG-word freshness (the 391 slice, on record). Where a money-pump leg or a supply race
touches solvency/redemption reconciliation or a permissionless entrypoint, surface the ECON half and
cross-ref the solvency half to 390 and the permissionless-composition half to 393.

## KNOWN BY-DESIGN (do NOT flag — settled rulings, out of scope for this slice)

- **EV > 100% RTP, positive-EV lootbox + coinflip, refund floors, charity governance**
  ([[intended-game-mechanics-not-findings]]) are NOT findings. The Degenerette engine is calibrated
  RTP > 100% by design; do not flag "RTP too high".
- **Degenerette RTP > 100% and the deliberately-near-worthless WWXRP token are by-design economics**
  ([[degenerette-wwxrp-rtp-by-design]]). The WWXRP token's only value is the near-unfarmable whale pass —
  verify the scarce whale-pass SUPPLY (one half-pass per bracket) and the BOUNDED accrual, NOT the WWXRP
  RTP or the WWXRP worthlessness.
- **Lootbox / redemption claim/open TIMING is not a player edge** ([[lootbox-resolution-timing-by-design]]).
  The open is permissionless and economically-incentivized; do not flag day/level/wait-to-open steering as
  an economic edge.
- **The documented EV-multiplier lift and the recycle relaxation (Class B above) are economics to VERIFY,
  not re-litigate.** Confirm the documented numbers and the binding cap; do not argue the lift is too large.
- Operator-approval as the trust boundary; afking inclusive eviction; `claimBingo` no level guard; the
  far-future salvage quote being publicly known (a settled deterministic pricing quote) — settled rulings,
  do not re-open.

## The thesis to BREAK (mapped to ECON-01..06)

We believe ALL of the following hold. Find a concrete counterexample to any one:

1. **(ECON-01 — bounded accrual)** Every reward consumer saturates BELOW its hard ceiling — the
   activity-score 65,534 hard cap (`ACTIVITY_SCORE_HARD_CAP_BPS`), the EV-multiplier 145% ceiling +
   10-ETH-per-(player,level) benefit cap, the Degenerette/WWXRP ROI 30,500-bps saturation
   (`ACTIVITY_SCORE_MAX_BPS`), the terminal-decimator streak re-clamp to 100 — so NO input (the now-uncapped
   quest streak `bonusBps += questStreak * 50`, uint16, included) pushes any reward PAST its prior
   saturation ceiling. There is no unbounded grind.
2. **(ECON-02 — EV-neutral redistributions hold in code)** Each Class-A redistribution's coded arithmetic
   matches the documented EV-neutral target: the split 40/15/15/15/10/5; the ticket budget ×11/9 = 19,678
   bps; the far/near 0.2×1.5 + 0.8×0.875 = 1.0; the variance ranges centered on the old per-tier value with
   EV 0.786× preserved; the survival flip ×2 at p=0.5. No redistribution diverges from its claimed target.
3. **(ECON-03 — the two genuine EV changes match documented intent)** The EV band IS 9000–14500 bps with
   score-to-ceiling 40,000 (the documented lift), and the recycle gate IS `totalClaimableUsed >= priceWei*3`
   with the drain-detection removed (the documented relaxation). The coded numbers match the documented
   numbers; nothing else silently changed EV.
4. **(ECON-04 — no money pump)** NO closed positive-EV money pump exists across the COMPOSED reward surfaces
   (recycle kicker + presale box-credit + spin recirc + auto-rebuy carry + affiliate flip-credit) — no
   repeatable cycle where realized value-out exceeds value-in.
5. **(ECON-05 — scarce-asset supply intact)** The box WWXRP-spin whale-half-pass channel stays
   near-unfarmable and the per-bracket supply is ONE half-pass regardless of acquisition route — no path
   mints a half-pass beyond the per-bracket cap.
6. **(ECON-06 — streak rate-bounded + decay-gated)** The now-uncapped/halved quest streak is rate-bounded
   (≤3/day) and decay-gated (the off-run decay anchor is the daily primary; miss a day and the manual streak
   reads 0) so the activity-score ceiling is reachable only by intended sustained effort.

## Authoritative frozen line-cites (read the code via `git show a8b702a7:...`, do not trust the cite blindly)

- `contracts/DegenerusGameStorage.sol`: `LOOTBOX_EV_ACTIVITY_MAX_BPS = 40_000` + the EV band 9000–14500
  @~1537-1548 (`_lootboxEvMultiplierFromScore`); `ACTIVITY_SCORE_HARD_CAP_BPS = 65_534` @~140 (uint16-1
  sentinel, the sDGNRS redemption snapshot stores `uint16(score)+1`); `ACTIVITY_SCORE_MAX_BPS = 30_500`
  (ROI / WWXRP saturation); `_effectiveQuestStreak(player)` @2284 (single source of truth);
  `_afkingStreak` @2257 (streak base + funded delivered days); `lootboxEvCapPacked` two-window store
  @~1698-1707 (the per-(player,level) `usedBenefit` cap state).
- `contracts/modules/DegenerusGameMintStreakUtils.sol`: `bonusBps += uint256(questStreak) * 50` @313-315
  (was ×100, the 100-completion cap removed); the hard-cap clamp to 65,534 @349-351.
- `contracts/modules/DegenerusGameLootboxModule.sol`: `_applyEvMultiplierWithCap` @474 (the per-(player,
  level) `LOOTBOX_EV_BENEFIT_CAP = 10 ether` `usedBenefit` RMW); the stale EV-band comment @472-473 (says
  8000-13500 after the band moved to 9000-14500); `_resolveLootboxRoll` @~1965 (the `roll % 20` split + the
  `allowEthSpin` gate); recirc entry `allowEthSpin=false`; redemption ETH-spin `allowEthSpin=true`.
- `contracts/modules/DegenerusGameDegeneretteModule.sol`: `resolveWwxrpSpinFromBox` @1292 (guard
  `address(this) != GAME` @1298; the S==9 whale-half-pass award @1323-1330; the per-bracket global flag
  `wwxrpJackpotWhalePassBracketAwarded[bracket]`, bracket = `level/10`); `resolveBurnieSpinsFromBox` @1347
  (survival flip `hash2(seed, BOX_SURVIVAL_TAG) & 1`); `resolveEthSpinFromBox` @~1400 (the 3-tier
  `_distributePayout` → claimable ETH + recirc box, `allowEthSpin=false` on recirc → recursion depth 1);
  the regular-bet WWXRP bracket `level/10` (the unchanged twin); `_roiBpsFromScore` (ROI saturation);
  `BOX_BETID_SENTINEL = 1<<63` (the BoxSpin event-decode sentinel).
- `contracts/modules/DegenerusMintModule.sol`: the recycle kicker @1740-1744 (now ONLY
  `totalClaimableUsed >= priceWei*3`, the `spentAllClaimable` drain block deleted); the presale 25%
  box-credit @1726 (`presaleBoxCredit`).
- `contracts/DegenerusQuests.sol`: `_questCompleteWithPair` @~1700-1760 (per-completion streak credit; the
  `afking` branch skips the manual +1 for slot 0); `_handleLevelQuestProgress` @2063-2068 (the level-quest
  `qs.streak += 1`, NOT gated by the daily primary off-run, the decay anchor NOT updated by it);
  `_secondaryLocked` @1529 (off-run the secondary requires the primary; while afking it does not); the
  decay anchors `lastActiveDay`/`lastCompletedDay` updated only on slot 0.
- `contracts/modules/GameAfkingModule.sol`: `recordAfkingSecondary` @1714 (`subStreakLatch += 1` saturating
  at 255; widened from a 7-bit 0-100 field to full uint8).
- `contracts/modules/DegenerusGameDecimatorModule.sol`: `_terminalDecBoostFactorBps` @~956 (re-clamps the
  streak to 100, the boost factor clamped 20×).
- `contracts/DegenerusAffiliate.sol`: `payAffiliate` access GAME-only @414-419 (the COIN path removed);
  the 75/20/5 winner-takes-all + the no-referrer 50/50 VAULT/DGNRS split via `coinflip.creditFlip` (illiquid
  BURNIE flip-credit); `getReferrer`/`_referrerAddress` fall back to VAULT (chains always terminate at
  VAULT, never address(0)); `affiliateBonusPointsBest` early-break once `sum >= 25 ether`
  (`AFFILIATE_BONUS_MAX`) @725-726.
- Reference: BURNIE:tickets ETH-value ratio from lootboxes ≈ **0.59 : 1** (tickets ≈ 1.69× BURNIE);
  BURNIE valued at the protocol peg (1000 BURNIE = 1 whole-ticket price), realizable value LOWER (illiquid
  flip-credit). Green oracle: `test/REGRESSION-BASELINE-v63.md` = forge 854/0/110. Frozen-source read
  convention: `git show a8b702a7:contracts/<File>.sol` (ignore the working tree).

## Concrete break-targets (charge the money-pump search + the two prime leads HARD)

### 1. (PRIME — ECON-04, HIGH-if-real — the DEDICATED money-pump search)

Hunt for ANY closed positive-EV loop where realized value-out EXCEEDS value-in across a REPEATABLE cycle,
COMPOSING the surfaces that each individual map rated EV-neutral IN ISOLATION. The legs to compose:
- the **recycle kicker** — 10% illiquid BURNIE flip-credit on a ≥3-whole-ticket recycled spend
  (`DegenerusMintModule.sol:1740-1744`);
- STACKED with the **presale 25% box-credit** on the SAME recycled spend
  (`DegenerusMintModule.sol:1726`);
- the **spin recirc** — the ETH-spin (`resolveEthSpinFromBox`, `DegeneretteModule:~1400`) splits via the
  3-tier rule into claimable ETH + ONE recirc box, which itself rolls again (depth-1) and can re-hit a
  spin;
- the **auto-rebuy carry** — the perpetual 0-take-profit rebuy roll (`claimCoinflipCarry`) that compounds
  win-after-win;
- the **affiliate flip-credit** — the 75/20/5 winner-takes-all routed via `coinflip.creditFlip`.

Charge the council to EITHER **CONSTRUCT a concrete repeatable cycle whose realized value-out > value-in** —
spelling out the ordered call sequence, the per-leg value flows, and the net per-cycle gain, accounting for
(a) BURNIE flip-credit illiquidity (it must survive a coinflip before it mints, valued below the peg), (b)
the sub-100% DIRECT lootbox EV (the EV multiplier floor is 90%, neutral at score 6,000 = 100%, and the
recycled spend buys boxes whose direct EV is the box's own EV not a guaranteed gain), (c) the 10-ETH
per-(player,level) benefit cap that bounds the EV uplift, and (d) the requirement that claimable must FIRST
be WON (a positive-variance event) before it can be recycled — OR state **VERIFIED SOUND** with the
CONCRETE reason no composition closes a positive loop (e.g. every leg's OUTPUT is illiquid / sub-100% /
capped, while the cycle's INPUT is real won claimable that exceeds the illiquid value-out, so the loop is
strictly value-LOSING per cycle). A hand-wave ("each leg is EV-neutral so the composition is fine") is NOT
acceptable — require the per-leg value accounting across the composed cycle, because the v60/v62 findings
were precisely compositions that each map rated safe in isolation.

### 2. (PRIME — ECON-05 / FC-392-07, MED — the whale-half-pass acquisition-cost target)

The box WWXRP-spin (15% of opens) can hit S==9 and award the bracket's one whale half-pass
(`resolveWwxrpSpinFromBox` @1323-1330) — a NEW acquisition channel vs only deliberate WWXRP bets. The
per-bracket flag `wwxrpJackpotWhalePassBracketAwarded[bracket]` is GLOBAL and SHARED (with the regular
WWXRP-bet jackpot route), so total SUPPLY is claimed to stay one half-pass per 10-level bracket. Charge the
council to:
- **QUANTIFY the new acquisition cost**: P(S==9) for a 1-WWXRP-staked box spin × the expected boxes-per-pass
  (factoring the 15% WWXRP-spin slice of opens), and confirm the cost still EXCEEDS the by-design
  "near-unfarmable" bar — a cost-curve change with supply intact is the DOCUMENTED channel change (not a
  finding); a cost low enough to make the pass routinely farmable would be a material economic shift to
  surface;
- **confirm no path mints a half-pass BEYOND the per-bracket cap** — the value-bearing supply break. Trace
  (i) a RACE between the box-spin route and a deliberate-WWXRP-bet route both reaching the
  `wwxrpJackpotWhalePassBracketAwarded[bracket]` write within the same bracket (could two awards both read
  the flag as unset before either writes it — a check-then-set gap?), and (ii) a recirc box re-rolling the
  WWXRP-spin within ONE open (could one open award two half-passes via the recirc depth-1 path?).

A real SUPPLY break (>1 half-pass per bracket) is value-bearing — surface it with the exact write sequence.
A mere cost-curve change with the supply flag intact is the documented channel change — state VERIFIED SOUND
with the flag-write ordering that guarantees at-most-one.

### 3. (PRIME — ECON-04 / SOLV cross-ref / FC-392-08, MED — the redemption ETH-spin value-extraction surface)

The redemption claim path (`allowEthSpin=true`) reaches the ETH-spin whose `_distributePayout` does a live
ETH-pool read-modify-write + a recirc box INSIDE the redemption claim (the V62-03 / council CEI region).
Charge the council to surface the ECON-level VALUE-EXTRACTION half:
- whether the recirc box's `_applyEvMultiplierWithCap` benefit-cap RMW can be RACED across redemption
  chunks to RE-EARN the 10-ETH cap (the cap re-earn = an EV uplift beyond the documented bound), and
- whether the ETH-spin within the redemption path can realize EV beyond the documented "EV-equal to the
  tickets it replaces" claim once it runs through the >100%-RTP Degenerette payout + the recirc cascade.

NOTE this is the ECON-economics half ONLY — the solvency-CEI / stETH-before-ETH / reentrancy half is owned
by the 390 (SOLV) slice and the permissionless-composition half by the 393 (ACCESS) slice. Surface any
ECON-level value-extraction (cap re-earn / EV uplift beyond the documented bound) and explicitly CROSS-REF
the solvency-reconciliation half (the ETH-spin pool writes + the dust-forfeit leg +
`pendingRedemptionEthValue` release reconciling exactly) to the 390 slice — do not duplicate the solvency
adjudication here.

## The remaining owned reward-economics leads (numbered break-targets at map severity)

### 4. (FC-392-01 / FC-392-02, LOW — ECON-06 streak gaming)

Two streak-gaming surfaces:
- **FC-392-01:** the level-quest +1 streak is NOT gated by the daily primary off-run
  (`_handleLevelQuestProgress` @2063-2068 credits `qs.streak += 1` with no primary-completed check; the
  decay anchor is NOT updated by it). Find any path where the off-day level-quest +1 is NOT zeroed by the
  next-day decay when the primary is skipped — a persistent streak bump bypassing the primary gate.
- **FC-392-02:** the afking-secondary double-channel — while afking, both `recordAfkingSecondary`
  (`subStreakLatch += 1`) and the funded delivered day count toward streak. Find any toggling of afking
  on/off across a day boundary that harvests BOTH the funded-day streak AND a manual +1 for the same primary
  (the `afking` branch in `_questCompleteWithPair` is supposed to skip the manual +1 for slot 0).

Confirm the decay + the rate-bound (≤3/day; level-quest once per level) keep the ceiling reachable only by
intended sustained effort, OR surface a finding. (Bounded streak gaming that the decay zeroes is INFO/LOW; a
persistent bypass of the daily-primary gate that survives decay is the finding.)

### 5. (FC-392-05 / FC-392-06 / FC-392-09, INFO-LOW — VERIFY-claim, the EV-cap bound under composed paths)

The per-(player,level) 10-ETH `usedBenefit` cap (`_applyEvMultiplierWithCap` @474) is now reached on a
SMALLER staked notional with the 145% ceiling. These are VERIFY-claim targets (the documented EV changes) —
verify the bound binds, do NOT re-litigate the documented lift:
- **FC-392-05:** confirm the `usedBenefit` cap CANNOT be RESET within a level to re-earn the uplift across
  the paths that all funnel into `_applyEvMultiplierWithCap` (redemption + direct-open + Degenerette-recirc)
  — the per-(player,level) keying must persist across all three.
- **FC-392-06:** confirm the recycle kicker stays EV-neutral-or-negative (illiquid flip-credit + flip
  survival) and does NOT form a positive loop when STACKED with the presale box-credit on the same recycled
  spend (the LOCAL view of the ECON-04 composition — feeds break-target 1).
- **FC-392-09:** confirm the ETH-spin "EV-equal to the tickets it replaces" claim holds given it runs
  through the >100%-RTP Degenerette payout + recirc — i.e. the aggregate box EV uplift (this + the §2 band
  widening + the WWXRP/BURNIE conversions) is BOUNDED by the 10-ETH benefit cap.

### 6. (FC-392-03 / FC-392-04 / FC-392-10, INFO — VERIFY-claim + comment/sentinel staleness)

- **FC-392-03 (VERIFY-claim):** the faster decimator-max ramp (20× boost in ~33 active days vs ~100, from
  the ×3-faster streak growth) — verify the documented intent matches the coded ramp (the streak re-clamp to
  100 keeps the terminal boost ceiling unchanged; only the time-to-ceiling shortened).
- **FC-392-04 (comment-staleness):** the stale EV-band comment (`LootboxModule:472-473` says 8000-13500
  after the band moved to 9000-14500) — a comment-only economic-spec staleness to note, NOT a logic finding.
- **FC-392-10:** the `BoxSpin` betId sentinel collision (`BOX_BETID_SENTINEL = 1<<63`) — confirm a real bet
  nonce can never reach bit 63 over the game lifetime so the event-decode stays correct.

### 7. (FC-392-14 / FC-392-15, LOW-INFO — affiliate composition)

The VAULT-terminating referral chains + 75/20/5 winner-takes-all:
- **FC-392-14:** confirm a self-referral / circular-code attempt CANNOT route the upline1/upline2 (20/5%)
  slices back to the sender, and the no-referrer 50/50 VAULT/DGNRS path CANNOT be steered by choosing a code
  that flips `noReferrer` to capture the affiliate 75% slice for an attacker-controlled address.
- **FC-392-15:** re-examine the carried v62 affiliate-score asymmetry against the now-GAME-only
  `payAffiliate` access (@414-419) + the `affiliateBonusPointsBest` 25-ether early-break (@725-726) to
  confirm the asymmetry did not change (the early-break is claimed SAFE for monotonic accumulation: sum only
  grows, clamps at 25 ether, so the early exit returns the same clamped result).

These feed the ECON-04 composition (the affiliate flip-credit leg) — confirm no positive loop and no
value-redirect.

## ECON-01 bounded-accrual sweep (the explicit per-surface ceiling check)

For EACH reward surface in the bounded-accrual table below, confirm the named hard bound BINDS (the consumer
saturates BELOW the cap) and find ANY surface where the now-uncapped quest-streak input (uint16,
rate-bounded ≤3/day, `bonusBps += questStreak * 50`) can push a downstream reward PAST its prior saturation
ceiling:

| Reward surface | Uncapped input? | Hard bound that must bind |
|---|---|---|
| Activity score (quest streak ×50 uncapped) | streak unbounded (uint16) | `ACTIVITY_SCORE_HARD_CAP_BPS = 65,534`; every consumer saturates lower |
| Lootbox EV multiplier | score | 145% ceiling at score 40,000 + 10-ETH/(player,level) benefit cap |
| Degenerette ROI / WWXRP ROI | score | `ACTIVITY_SCORE_MAX_BPS = 30,500` saturation |
| Terminal-decimator boost | streak | streak re-clamped to 100; boost factor clamped 20× |
| BURNIE survival flip | per-bet | EV-neutral ×2 at p=0.5; bounded per bet |
| Lootbox spins (WWXRP/BURNIE/ETH) | box amount | inherits the capped scaled box amount; recirc depth 1 |
| Recycle bonus | recycled claimable | 10% illiquid flip-credit; no closed loop |
| Whale half-pass via box WWXRP-spin | box opens | one half-pass per 10-level bracket (global flag) |
| BURNIE seed emission | — | flip-survival before mint; supply invariant intact |

The load-bearing claim: every consumer saturates BELOW the 65,534 hard cap (EV at 40,000; ROI/WWXRP at
30,500; the decimator re-clamps the streak to 100), so the uncapped streak cannot WIDEN any reward ceiling —
it only shortens the time-to-ceiling. Confirm each row, or surface the surface where the uncapped streak
breaches a downstream ceiling.

## Output (per item)

For each break-target AND each thesis point (ECON-01..06), state ONE of:
- **FINDING:** PROPERTY broken · reachable ordered CALL SEQUENCE (the repeatable cycle for a money pump;
  the acquisition cost + the write race for the whale pass; the multi-day grind for unbounded accrual; the
  coded value vs the documented EV-neutral target for a redistribution divergence) · STATE VAR + `file:line`
  at `a8b702a7` · SEVERITY (per the threat priority above — a closed positive-EV money pump is HIGH; a
  scarce-asset supply over-mint and an unbounded accrual are value-bearing) · WHY the existing cap /
  saturation ceiling / flip-credit illiquidity / per-bracket flag / decay gate does NOT stop it.
- **VERIFIED SOUND:** the property and the SPECIFIC reason it holds — cite the binding cap, the saturation
  ceiling, the EV arithmetic (the per-leg value accounting for a money-pump claim), the supply flag's
  at-most-one write ordering, or the decay anchor — so the adjudicator can confirm your reasoning. A
  hand-wave is not acceptable for the money-pump and whale-pass prime targets; require the value accounting
  / the write-ordering proof.

Do NOT pre-state a verdict you have not traced to source. Read the frozen tree at `a8b702a7` via
`git show`. The council finds; the adjudicator (Claude) reconciles at 392-03.
