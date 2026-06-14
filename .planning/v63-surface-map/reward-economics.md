# v63 Surface Map — Reward Game-Theory & Economics (EV / RTP / Incentive Alignment)

BASELINE 77580320 → SUBJECT a8b702a7. READ-ONLY characterization for milestone scoping.
This dimension covers reward accrual bounds, EV/RTP rebalances, streak/score gaming, and
new dominant-strategy surfaces. Severity hints are conservative; candidate focus areas are
leads for a later adversarial sweep, not confirmed findings.

---

## 1. Unified activity score + quest streak halved & uncapped (commit 9d178bc0)

### What changed
- Quest streak now credits on EVERY completion — primary (slot 0), secondary (slot 1), and
  level quest — each independently, up to ~3/day (was: once per day, the
  `QUEST_STATE_STREAK_CREDITED` bit removed). `DegenerusQuests.sol` `_questCompleteWithPair`
  (~line 1700-1760) and `_handleLevelQuestProgress` (~line 2058-2068).
- Per-completion score contribution HALVED from 1% (100 bps) to 0.5% (50 bps), and the old
  100-completion cap REMOVED. `DegenerusGameMintStreakUtils.sol:313-315`
  (`bonusBps += uint256(questStreak) * 50`).
- New global ceiling: `ACTIVITY_SCORE_HARD_CAP_BPS = 65_534` applied to the TOTAL score.
  `DegenerusGameStorage.sol:~140`, applied at `MintStreakUtils.sol:349-351`. The value is
  deliberately one below uint16 max because the sDGNRS redemption snapshot stores
  `uint16(score) + 1` (0 = unset sentinel) — `StakedDegenerusStonk.sol:1087`.
- Single source of truth `_effectiveQuestStreak(player)` (`DegenerusGameStorage.sol:2284`)
  replaces direct `quests.effectiveBaseStreak()` reads in Decimator, Degenerette, Whale, and
  Game `playerActivityScore`. A live afking sub reads the Sub-side compute-on-read; everyone
  else (and lapsed runs) reads the manual decay-aware streak.
- Afking-secondary parity: a secondary/level completion while afking calls
  `recordAfkingSecondary` (`GameAfkingModule.sol:1714`) which bumps the Sub streak base
  (`subStreakLatch`) by +1, saturating at 255. The afking-streak compute-on-read
  (`_afkingStreak`, `DegenerusGameStorage.sol:2257`) = streak base + funded delivered days;
  the funded auto-buy stands in for the primary. The byte width of `subStreakLatch` widened
  from a 7-bit field (0-100 snapshot) to a full uint8 (0-255).
- `_secondaryLocked` (`DegenerusQuests.sol:1529`): off-run the secondary still requires the
  primary that day; while afking it does not (the funded auto-buy is the primary).

### Game-theory analysis
- **Max score is still bounded.** Every downstream consumer saturates BELOW the 65,534 hard
  cap: lootbox EV multiplier saturates at `LOOTBOX_EV_ACTIVITY_MAX_BPS = 40_000`; Degenerette
  ROI (`_roiBpsFromScore`) and WWXRP high ROI saturate at `ACTIVITY_SCORE_MAX_BPS = 30_500`;
  terminal-decimator boost re-clamps the streak itself to 100 (`_terminalDecBoostFactorBps`,
  `DecimatorModule.sol:956`). So the uncapped streak cannot push any reward past its prior
  saturation ceiling. Reward accrual remains bounded.
- **Ramp is ~3x faster.** The marginal score gain from streak went from +100 bps/day (1×100)
  to +150 bps/day (3×50). To reach decimator-max (streak 100) is now ~33 days instead of 100.
  To saturate ROI (30,500 bps) from streak alone is ~610 completions ≈ 203 days; to saturate
  EV (40,000 bps) ≈ 800 completions ≈ 267 days. The CEILINGS are unchanged; only the time-to-
  ceiling shortened. This is the documented intent of "halve + uncap", but it is a genuine
  economic rebalance (faster access to max EV / max decimator weight for active players).
- **Streak growth is rate-bounded** (≤3/day) and **decay-gated**: off-run the decay anchor is
  the primary (`lastActiveDay`/`lastCompletedDay`, both now updated ONLY on slot 0). Miss a day
  (beyond shields) and the manual streak reads 0 (`_effectiveBaseStreak`). So a high streak
  requires daily primary completion — not free.
- **Truncation safety.** `uint16(activityScore)` is taken in WhaleModule:871,
  StakedDegenerusStonk:1087, GameAfkingModule:875. All are safe because the hard cap (65,534)
  fits in uint16; the `+1` redemption sentinel maxes at 65,535 = uint16 max (no overflow). The
  read-back decrement is correct (`StakedDegenerusStonk.sol:873`).

### Candidate focus areas
- **FA-1 (LOW): Level-quest +1 streak is NOT gated by the daily primary off-run.**
  `_handleLevelQuestProgress` (`DegenerusQuests.sol:2063-2068`) credits `qs.streak += 1` on a
  level-quest completion gated only by `_isLevelQuestEligible` and once-per-level, with no
  check that the daily primary completed. The decay anchor (primary) is NOT updated by it, so
  the +1 is at decay risk next day — but it is locked into `state.streak` immediately. A player
  could bump streak via a level quest on a day with no primary. Bounded by level-progression
  rate (one level-quest per level), so not unbounded, but it is an off-day streak increment
  that bypasses the primary gate. Worth confirming the decay still zeroes it correctly when the
  player then skips the primary.
- **FA-2 (LOW/INFO): afking secondary double-channel.** While afking, both a secondary
  (`recordAfkingSecondary`) and the funded delivered day count toward the streak. Verify no
  path lets a single day's funded delivery AND a manual primary both count (the primary is
  supposed to be streak-neutral while afking — `afking` branch in `_questCompleteWithPair`
  skips the manual +1 for slot 0). Confirm a player toggling afking on/off across a day
  boundary cannot harvest both the funded-day streak and a manual +1 for the same primary.
- **FA-3 (INFO): faster decimator-max ramp.** Reaching the 20x terminal-decimator boost in
  ~33 active days vs ~100 is an intended but real rebalance of terminal-jackpot weight
  concentration toward fast-ramping players; confirm the documented intent matches.

---

## 2. Lootbox EV-multiplier + reward-split + ticket-distribution rebalance (commit dae8e775)

### What changed
- EV multiplier band widened: MIN 8000→9000 bps (90% floor at 0 activity), MAX 13500→14500 bps
  (145% at max), and the max-activity threshold 25500→40000 bps. Neutral unchanged (60%
  activity = 100% EV). `DegenerusGameStorage.sol:1537-1548`, `_lootboxEvMultiplierFromScore`.
- Reward path split (at this stage): tickets 55%→45%, DGNRS 10%→15%, WWXRP 10%→15%, BURNIE
  flat 25% (unchanged). `_resolveLootboxRoll`.
- Far/near target-level split: far-future (5-50 levels) chance 10%→20%; near (0-4) 90%→80%.
  Ticket budget weighted 1.5x far / 0.875x near (`LOOTBOX_TICKET_FAR_BUDGET_BPS = 15_000`,
  `LOOTBOX_TICKET_NEAR_BUDGET_BPS = 8_750`).
- Base ticket-roll BPS 16_100→19_678 (= 16100 × 11/9, preserving aggregate ticket value across
  the 55%→45% frequency drop).
- Variance tiers converted from static per-tier multipliers to symmetric BPS bands about the
  prior static value, drawn uniformly within the tier window from the SAME varianceRoll (no
  extra entropy). Per-tier means and overall variance EV preserved.

### Game-theory analysis (math verified)
- Far/near EV factor = 0.2×1.5 + 0.8×0.875 = **1.000** (exactly EV-neutral).
- Aggregate ticket value: old 0.55×16100 = 8855; new 0.45×19678 = 8855.1 (**preserved**).
- Variance-tier EV: new = 0.78595 = old (**preserved**).
- The EV-multiplier WIDENING is a real, intended buff (max EV 135%→145%, min 80%→90%), gated
  by the per-account-per-level `LOOTBOX_EV_BENEFIT_CAP = 10 ether` (`_applyEvMultiplierWithCap`,
  `LootboxModule.sol:474`). The cap binds the total EV uplift regardless of box count, so the
  buff cannot compound into unbounded extraction.

### Candidate focus areas
- **FA-4 (LOW): stale EV-band comments.** `LootboxModule.sol:472-473` still document
  "8000-13500" / "EV multiplier in basis points (8000-13500)" after the band moved to
  9000-14500. Comment-only; no logic impact, but a stale economic spec.
- **FA-5 (INFO): EV-multiplier benefit-cap interaction with the wider band.** With max EV now
  145% (was 135%) the per-level 10 ETH benefit cap is reached on a smaller staked notional.
  Confirm the cap accounting (`usedBenefit` per (player, level)) cannot be reset within a level
  to re-earn the uplift (e.g., across redemption + direct-open + Degenerette-recirc paths that
  all funnel into `_applyEvMultiplierWithCap`).

---

## 3. Mint recycle bonus relaxed to >=3-ticket claimable threshold (commit a85c61b3)

### What changed
- OLD: 10% BURNIE flip-credit bonus required spending ALL claimable (`spentAllClaimable`, a
  drain-to-near-zero check) AND `totalClaimableUsed >= priceWei * 3`.
- NEW: only `totalClaimableUsed >= priceWei * 3` (≥3 whole tickets' worth recycled), regardless
  of remaining claimable balance. `MintModule.sol:1740-1744`. The drain-detection block was
  deleted.

### Game-theory analysis
- The bonus is 10% of recycled value, paid as BURNIE flip-credit (illiquid — must survive a
  coinflip before it mints). The recycled value is the player's OWN already-won claimable
  ETH-value, spent on tickets/boxes that have their own (sub-100% direct) EV.
- **No closed positive-EV loop.** Output (10% illiquid BURNIE) << input (real claimable spent
  on tickets). To get claimable you must first win it (positive-variance event). The bonus is a
  recycling kicker, not a money pump.
- The relaxation purely LOWERS the qualification threshold (no need to drain to zero), so a
  player can keep a claimable reserve and still earn the kicker. Per-trigger magnitude
  (10% of recycled) is unchanged; it is now easier to trigger on every qualifying buy.

### Candidate focus areas
- **FA-6 (LOW): repeatable recycle kicker on partial spends.** Because the all-claimable gate
  is gone, a whale with a large claimable balance can now earn the 10% kicker on EVERY buy that
  recycles ≥3 tickets' worth, while retaining most of their balance — previously each kicker
  required a full drain. Confirm the BURNIE flip-credit illiquidity + flip-survival gate keeps
  this EV-neutral-or-negative and that there is no interaction with the presale 25% box-credit
  (`MintModule.sol:1726`) that stacks into a positive loop when both fire on the same recycled
  spend.

---

## 4. Lootbox Degenerette spins + BoxSpin event (commit a8b702a7)

### What changed
Three lootbox value rolls now resolve as Degenerette spins instead of flat awards
(`_resolveLootboxRoll`, `LootboxModule.sol:~1950`). New split (roll % 20):
- 40% tickets (was 45%)
- 15% DGNRS
- 15% WWXRP-spin — was a flat 1-WWXRP mint; now a Degenerette spin STAKING 1 WWXRP
  (`resolveWwxrpSpinFromBox`, `DegeneretteModule.sol:1292`)
- 15% BURNIE flat (creditFlip)
- 10% BURNIE-spins ×3 under one survival flip, stake = the would-be large BURNIE
  (`resolveBurnieSpinsFromBox`, `DegeneretteModule.sol:1347`), mint-only
- 5% ETH-spin (direct boxes only; `allowEthSpin`) — stake = the ticket budget it replaces
  (EV-equal), splits via the 3-tier ETH `_distributePayout` + recircs into one fresh box
  (`resolveEthSpinFromBox`, `DegeneretteModule.sol:~1400`)
- Spin sub-seeds are `hash2(seed, BOX_*_SPIN_TAG)` — counter-tagged, consume no primary bits.
- Recirc box opened with `allowEthSpin=false` → ETH-spin cannot cascade (recursion depth 1).
- New packed `BoxSpin` event replaces per-spin FullTicketResult for box rolls.

### Game-theory analysis
- **EV direction.** Converting a flat ticket-equivalent (5%), flat BURNIE (10%), and flat WWXRP
  (15%) into Degenerette spins generally PRESERVES or slightly INCREASES EV because the
  Degenerette RTP is calibrated >100% by design (per the standing by-design ruling: +5% ETH
  bonus, big wins recirculate into lootboxes). The ETH-spin stake is explicitly "EV-equal to the
  tickets it replaces". This is consistent with the parallel EV-band buff in §2 and the
  documented intent of routing more box value through the >100%-RTP Degenerette engine.
- **Survival flip is EV-neutral** (×2 at 50/50) and freeze-safe: seed = box seed, committed
  before the VRF word lands; a losing flip pays zero whether resolved or abandoned, so selective
  resolution earns nothing (`DegeneretteModule.sol:759-775` for bets;
  `resolveBurnieSpinsFromBox` for box). Upholds the "all BURNIE survives a coinflip before
  minting" invariant for the box BURNIE path.
- **Recursion bounded.** ETH-spin → 1 recirc box (allowEthSpin=false there). The recirc box can
  still roll WWXRP-spin / BURNIE-spins, but those are mint-only (no further recirc). No
  unbounded cascade.
- **WWXRP-spin → whale-halfpass route.** The box WWXRP-spin can hit S==9 and award the bracket's
  one whale halfpass (`resolveWwxrpSpinFromBox:1323-1330`). This is a NEW route to the whale
  pass (previously only via real WWXRP bets). BUT the per-bracket flag
  (`wwxrpJackpotWhalePassBracketAwarded[bracket]`) is GLOBAL and SHARED with regular WWXRP
  jackpots — total supply stays one halfpass per 10-level bracket. The new route changes the
  COST CURVE to obtain a pass (every box open now has 15% × P(S==9) chance) but not the SUPPLY.

### Candidate focus areas
- **FA-7 (MED): box WWXRP-spin lowers the cost to farm a whale halfpass.** The whale pass is the
  one thing the standing ruling treats as valuable ("near-unfarmable whale pass"). The new
  box-spin route makes it obtainable from any lootbox open (15% WWXRP-spin × P(S==9 with
  MIN_BET_WWXRP-sized stake)) rather than only from deliberate WWXRP bets. Even though supply is
  capped per-bracket, the SWEEP should quantify P(S==9) for a 1-WWXRP-staked box spin and the
  expected boxes-per-pass, and confirm the cost still exceeds the by-design "near-unfarmable"
  bar. Adjacent to the existing `degenerette-wwxrp-rtp-by-design` ruling — flag for re-confirm,
  not auto-dismiss, because the acquisition channel changed.
- **FA-8 (MED): redemption ETH-spin pool RMW + recirc vs solvency CEI.** The redemption path
  (`_resolveRedemptionChunk`, `allowEthSpin=true`) now reaches the ETH-spin, whose
  `_distributePayout` does a live ETH-pool read-modify-write and a recirc box, inside the
  redemption claim. This is the exact region the prior council/V62-03 solvency findings touched
  (stETH-before-ETH CEI, yield-surplus reentrancy). The new pool RMW + recirc adds surface here.
  The SWEEP should trace whether the ETH-spin's pool writes + the dust-forfeit leg + the
  pendingRedemptionEthValue release still reconcile exactly, and whether the recirc box's
  `_applyEvMultiplierWithCap` benefit-cap RMW can be raced across chunks.
- **FA-9 (LOW): ETH-spin stake = ticket budget EV-equal claim.** The ETH-spin stake is
  `_ticketBudget(amount, isFarFuture) * _ticketVarianceBps(seed) / 10_000`, asserted EV-equal to
  the tickets it replaces. But the ETH-spin then runs through the >100%-RTP Degenerette payout +
  recirc, so the realized EV of the 5% ETH-spin slice is plausibly > the tickets it replaced.
  Confirm the aggregate box EV uplift (this + the §2 band widening + the WWXRP/BURNIE spin
  conversions) is intended and the 10 ETH benefit cap still bounds it.
- **FA-10 (INFO): BoxSpin betId sentinel collision.** `BOX_BETID_SENTINEL = 1<<63`; real bet
  nonces increment from 1. Confirm a player's real bet nonce can never reach bit 63 over the
  game's lifetime (it cannot realistically, but the event-decode correctness depends on it).

---

## 5. BURNIE coinflip-seeded emission rework (commit b11fd610)

### What changed
- The 2M BURNIE constructor mint to sDGNRS and the 2M virtual vault allowance are BOTH removed;
  `_supply` now starts fully zero (`BurnieCoin.sol:174`).
- `BurnieCoinflip` constructor stakes 200k BURNIE/day for days 1-20 to BOTH VAULT and SDGNRS as
  direct coinflipBalance writes (off-leaderboard, off-bounty). Nothing mints up front — each
  day's seed only becomes claimable BURNIE if it survives that day's flip.
- During the seed window, each settled sDGNRS win is claimed straight to its wallet balance
  (backs redemptions). At day 20 settle, sDGNRS arms PERPETUAL auto-rebuy (0 take-profit):
  every later flip credit rolls win-after-win until a loss. `sdgnrsAutoRebuyArmed` latch.
- New `claimCoinflipCarry(player, amount)` lets a player withdraw from the rolling auto-rebuy
  carry as minted BURNIE while staying on auto-rebuy (settles resolved days first, RNG-locked-
  gated). `BurnieCoinflip.sol:782`.
- Degenerette BURNIE payouts gain the per-bet survival flip (see §4).

### Game-theory analysis
- **Supply invariant intact.** `totalSupply + vaultAllowance = supplyIncUncirculated` holds
  trivially (both start at 0; all changes route through the same accounting). The 4M notional
  seed (200k×20 each side) emits ~50% in expectation through flip survival, so the realized
  initial supply is variance-dependent — intended (`burnie-emission-rework` memory). Every
  BURNIE now survives a coinflip before minting (the design principle), where before 4M was
  minted up-front by the constructor.
- **sDGNRS backing is now coinflip-luck-dependent during the seed window.** A bad-luck seed
  window leaves sDGNRS with less BURNIE backing than the old fixed 2M. This is an intended
  variance trade, but it shifts redemption backing from deterministic to stochastic. The
  perpetual auto-rebuy then compounds sDGNRS's position (win-after-win until a loss), so the
  backing is path-dependent.

### Candidate focus areas
- **FA-11 (MED): sDGNRS perpetual 0-take-profit auto-rebuy backing dynamics.** sDGNRS's BURNIE
  backing rolls win-after-win until a loss zeroes the pending stake. A single loss can wipe the
  accumulated carry. The SWEEP should model whether a sequence of losses (or a single large-
  carry loss) can drop sDGNRS backing below outstanding redemption obligations, and whether
  `claimCoinflipCarry` (player-pull from the carry) interacts with the sDGNRS-position settle
  to let a redeemer extract during a window where backing is mid-roll. The carry is "the pending
  day's stake" and is RNG-lock-gated — verify the lock window fully covers the roll application.
- **FA-12 (LOW): seed-stake leaderboard/bounty exclusion.** The seed stakes are direct
  coinflipBalance writes (not `_addDailyFlip`) specifically to stay off the top-bettor
  leaderboard, the bounty, and biggest-flip records. Confirm no code path reads
  coinflipBalance[d][VAULT|SDGNRS] for days 1-20 into a leaderboard/bounty computation that
  would mis-credit the protocol addresses (e.g., BAF bracket, biggestFlipEver).
- **FA-13 (INFO): claimCoinflipCarry settle ordering.** It settles resolved days (wins → carry,
  pending loss → zero) BEFORE withdrawing from the carry. Confirm the take-profit chunks that
  the settle banks into `claimableStored` plus the carry withdrawal cannot double-count a single
  win across the two channels.

---

## 6. Affiliate rework (commits across the range; payAffiliate access + winner-takes-all)

### What changed
- `payAffiliate` access narrowed from {COIN, GAME} to GAME only
  (`DegenerusAffiliate.sol:414-419`). The COIN-purchase affiliate path is removed.
- `getReferrer` / `_referrerAddress` now NEVER returns address(0) — unresolvable referrers fall
  back to VAULT, so referral chains always terminate at VAULT.
- Affiliate distribution uses a single shared payout-roll entropy for both the no-referrer 50/50
  (VAULT vs DGNRS) and the 75/20/5 winner-takes-all (affiliate / upline1 / upline2). Rewards
  routed via `coinflip.creditFlip` (illiquid BURNIE flip-credit).
- `handleAffiliate` interface narrowed to return only the leading `reward` word.
- `affiliateBonusPointsBest` early-break once `sum >= 25 ether` (the AFFILIATE_BONUS_MAX cap),
  `DegenerusAffiliate.sol:725-726`.
- Affiliate-score asymmetry was a carried v62 finding-candidate (per memory).

### Game-theory analysis
- The winner-takes-all roll has a KNOWN PRNG (documented accepted tradeoff: "EV-neutral,
  manipulation only redistributive between affiliates"). Narrowing the caller to GAME removes a
  trust edge. Rewards are illiquid flip-credit, so no immediate-cash extraction.
- The `sum >= 25 ether` early-break is a gas optimization that is SAFE for monotonic
  accumulation (sum only grows, and the cap clamps at 25 ether), so the early exit returns the
  same clamped result. No under-count.

### Candidate focus areas
- **FA-14 (LOW): VAULT-terminating referral chains + winner-takes-all.** With every chain now
  terminating at VAULT and the upline1/upline2 (20%/5%) slices, confirm a self-referral or
  circular-code attempt cannot route the upline slices back to the sender, and that the
  no-referrer 50/50 VAULT/DGNRS path cannot be steered by a player choosing a code that makes
  `noReferrer` true vs false to capture the affiliate 75% slice for an address they control.
- **FA-15 (INFO): carried affiliate-score asymmetry.** The v62 affiliate-score asymmetry
  finding-candidate was routed forward; re-examine against the now-GAME-only access and the
  `affiliateBonusPointsBest` 25-ether early-break to confirm it did not change the asymmetry.

---

## Summary of bounded-accrual verification

| Reward surface | Uncapped input? | Hard bound that binds |
|---|---|---|
| Activity score (quest streak ×50 uncapped) | streak unbounded (uint16) | score hard cap 65,534; consumers saturate lower |
| Lootbox EV multiplier | score | 145% max + 10 ETH/account/level benefit cap |
| Degenerette ROI / WWXRP ROI | score | ROI_MAX 99.9% / WWXRP 109.9% at score 30,500 cap |
| Terminal-decimator boost | streak | streak re-clamped to 100; factor clamped 20x |
| BURNIE survival flip | per-bet | EV-neutral ×2 at 50/50, freeze-safe seed |
| Lootbox spins (WWXRP/BURNIE/ETH) | box amount | inherits capped scaledAmount; recursion depth 1 |
| Recycle bonus | recycled claimable | 10% illiquid flip-credit; no closed loop |
| Whale halfpass via box WWXRP-spin | box opens | one halfpass per 10-level bracket (global) |
| BURNIE seed emission | — | flip-survival before mint; supply invariant intact |

No surface was found with unbounded reward accrual or an obvious closed positive-EV loop. The
rebalances are economically consistent with documented intent (EV-neutral splits verified by
arithmetic; EV-band widening and Degenerette-routing are intentional buffs gated by the 10 ETH
benefit cap). The highest-attention leads for the adversarial sweep are FA-7 (whale-pass
acquisition cost via box WWXRP-spin), FA-8 (redemption ETH-spin pool RMW vs solvency CEI), and
FA-11 (sDGNRS perpetual auto-rebuy backing dynamics) — each touches a value-bearing invariant
(scarce pass supply, redemption solvency) rather than pure reward magnitude.
