# Phase 331 — GAS-02 + GAS-04 Calibration Decision Record

**Authored:** 2026-05-27
**Contract HEAD:** `63bc16ca` (`contracts/` clean on disk this session; every cited `file:line` source-verified against the live tree — the 330 IMPL shifted lines/slots, so the line numbers below were re-read, NOT trusted from stale planning docs).
**Plan:** 331-04 — compute the calibration; **NO `contracts/*.sol` edit in this plan.** The constant landing is the SEPARATE `autonomous: false` USER-gated 331-05 diff (the v46 Phase 319 precedent `e4014f91`/`795e679d`).
**Calibration input:** `331-GAS-DERIVATION.md` §5 (the 331-01 measured worst-case marginals at N≥32, the converged column).
**Methodology floor (HARD):** `feedback_security_over_gas` (the self-crank round-trip ≤ 0 faucet floor is a hard invariant) + the CR-01 rule (peg the per-item MARGINAL, never a single-item total) + `feedback_bounty_exploit_uses_real_gas_not_peg_ref` (exploitability judged at REAL prevailing gas, not the 0.5 gwei reference).
**Analog:** `.planning/milestones/v46.0-phases/319-.../319-GAS-06-CALIBRATION.md` + `319-CR01-FIX.md` — this is the same derive→peg pass one phase up for the v49 keeper router.

---

## 0. Scope, the conversion, and the CR-01 rule (load-bearing)

The break-even keeper bounty is a deterministic function of the **measured worst-case marginal
gas at the 0.5 gwei reference** (`AUTO_GAS_PRICE_REF` — the peg reference, not a market price). It
is not a guess. The router pays a single flat-per-tx bounty per the D-07 model (`AfKing.sol:868-904`,
re-read this session):

```
unit       = (BOUNTY_ETH_TARGET * PRICE_COIN_UNIT) / mp          // AfKing.sol:870 — level-invariant break-even BURNIE
buy  leg   = (unit * BUY_RATIO_NUM) / BUY_RATIO_DEN  = unit*3/2   // :878  flat 1.5x per tx
advance    = unit * ADVANCE_RATIO_NUM * mult         = unit*2*mult // :884 2x x stall mult (mult in {1,2,4,6}; 0 = gameover, no bounty)
open  leg  = (unit * min(opened, OPEN_KNEE)) / OPEN_KNEE          // :890-891  1x at/above knee, pro-rated below
```

with `PRICE_COIN_UNIT = 1000 ether` (`AfKing.sol:233`) and `BOUNTY_ETH_TARGET` the ctor immutable
(`AfKing.sol:261`, set `:277`). `mp = IGame(GAME).mintPrice()` (`DegenerusGame.sol:2423-2425` →
`PriceLookupLib.priceForLevel(_activeTicketLevel())`).

**The measured marginals (331-GAS-DERIVATION.md §5, N≥32 converged column):**

| Calibration input | Measured gas | N | Source |
|-------------------|--------------|---|--------|
| `router_dowork_buy_per_player_marginal_gas`  | **40,224** (clean N32 37,986) | 32 | 331-GAS-DERIVATION §1/§5 |
| `router_dowork_open_per_box_marginal_gas`    | **89,287** (clean N32 85,967) | 32 | 331-GAS-DERIVATION §2/§5 |
| `router_dowork_advance_marginal_gas`         | **210,689** (base, mult=1; single step) | 1 | 331-GAS-DERIVATION §3/§5 |
| `router_dowork_dispatch_overhead_gas`        | **228,084** (conservative ceiling) | 1 | 331-GAS-DERIVATION §4/§5 |

**CR-01 rule (the load-bearing lesson from 319):** the per-item flat reward MUST be pegged to the
per-item MARGINAL at N≥32 — never a single-item TOTAL. At 319 the box reward was over-pegged ~2x by
using the single-box total (137,944) instead of the per-box marginal (~71,203), opening a Sybil
self-crank faucet on the multi-box path. 331-01 re-confirmed the gradient empirically (buy
N1=116,437→N32=37,986 ~3.06x; open N1=180,221→N32=85,967 ~2.10x). **Every value below is derived
from the N≥32 converged marginal.**

**Anti-exploit basis is REAL prevailing gas, NOT the 0.5 gwei reference** (`feedback_bounty_exploit_uses_real_gas_not_peg_ref`,
which the USER corrected twice in Phase 329). The 0.5 gwei reference fixes the break-even peg; the
faucet judgement values the keeper's real tx cost at 5–50+ gwei against the illiquid flip-credit
reward valued at the 0.5 gwei peg. Both framings are stated for every constant below.

---

## 1. What is actually GATED vs SURFACED (the calibration-target distinction)

| Symbol | File:line (verified `63bc16ca`) | Kind | Calibration disposition |
|--------|----------------------------------|------|--------------------------|
| `DOWORK_BATCH`      | `AfKing.sol:847` | frozen `internal constant` | **GATED** — confirm `100` |
| `ADVANCE_RATIO_NUM` | `AfKing.sol:849` | frozen `internal constant` | **GATED** — confirm `2` |
| `BUY_RATIO_NUM`     | `AfKing.sol:851` | frozen `internal constant` | **GATED** — confirm `3` |
| `BUY_RATIO_DEN`     | `AfKing.sol:852` | frozen `internal constant` | **GATED** — confirm `2` |
| `OPEN_KNEE`         | `AfKing.sol:854` | frozen `internal constant` | **GATED** — confirm `5` |
| `RESOLVE_FLAT_BURNIE` | `DegenerusGame.sol:1543` | frozen `private constant` | **GATED** — confirm `1e18` |
| `BOUNTY_ETH_TARGET` | `AfKing.sol:261` (immutable, set `:277` from ctor arg `_bountyEthTarget`; fixture `DeployProtocol.sol:126` = `885_000_000`) | **deploy-param immutable** | **SURFACED-NOT-GATED** — recommend a ceiling; the production value is a USER economic choice in the paired `degenerus-utilities` deploy script |

The five `AfKing.sol` `internal constant`s + `RESOLVE_FLAT_BURNIE` are frozen `contracts/*.sol`
literals → they are behind the USER-APPROVED 331-05 gate. `BOUNTY_ETH_TARGET` is a constructor
immutable supplied by the deploy script (AGENT-editable, NOT a frozen constant) — surfaced for the
USER exactly as 319 did with the same parameter.

---

## 2. The ratio constants encode the RELATIVE per-category marginals (a single shared `unit`)

A flat-per-tx model with ONE shared `unit` and per-category ratios can reimburse exactly ONE leg at
break-even; the other legs are deliberately UNDER-reimbursed (the anti-faucet margin). The ratio a
leg deserves is proportional to `marginal_gas(leg) / unit_gas` — so the relative marginals dictate
the relative ratios. The measured relative marginals (normalized to buy = 1.0):

| Leg | Marginal gas | Relative to buy | Current reward ratio (x `unit`) |
|-----|--------------|-----------------|----------------------------------|
| buy           | 40,224  | 1.00  | **1.5x** (`3/2`) |
| open at knee  | 89,287  | 2.22  | **1.0x** (`5/5`) |
| advance base  | 210,689 | 5.24  | **2.0x** (`2 * mult`, base mult=1) |

The ratios are NOT a 1:1 mirror of the relative marginals, and that is correct by design — the model
is a SINGLE shared `unit` (not three independent pegs). The relevant invariant is the per-leg
break-even: **each leg's reward, valued at the peg, must be AT or BELOW that leg's real marginal at
the 0.5 gwei reference (round-trip ≤ 0).** Section 3 proves a single shared `BOUNTY_ETH_TARGET` keeps
all legs simultaneously at/below their marginal.

The ratios were chosen so that the CHEAPEST-gas leg (buy, the highest-priority liveness leg the
keeper runs first every day) gets the RICHEST ratio (1.5x), and the most expensive leg (advance) is
NOT given a proportionally huge base ratio (only 2x) because the stall multiplier `mult` rides on top
(1/2/4/6) — the advance ladder is the escalation lever, not the base ratio. **Confirm 1.5 / 1.0 /
2.0 / knee=5 — the measured relative marginals support them (proof in §3); no ratio re-proposal.**

---

## 3. Faucet-floor analysis — the per-leg round-trip ≤ 0 proof

Reward credited per leg, valued back at the peg, recovers exactly `ratio * BOUNTY_ETH_TARGET` ETH (mp
cancels — §6). The keeper's REAL cost is `marginal_gas * (real gas price)`. Round-trip ≤ 0 ⟺
`ratio * BOUNTY_ETH_TARGET ≤ marginal_gas * (price)`. Rearranged, the per-leg ceiling on the shared
deploy-param at the 0.5 gwei reference is `BOUNTY_ETH_TARGET ≤ marginal_gas * 0.5gwei / ratio`:

| Leg | marginal_gas | ratio | `marginal/ratio` (gas-equiv) | Ceiling on `BOUNTY_ETH_TARGET` @0.5gwei ref (wei) |
|-----|--------------|-------|------------------------------|---------------------------------------------------|
| buy (clean N32) | 37,986  | 1.5  | **25,324** | **12,662,000,000,000** |
| buy (conservative) | 40,224 | 1.5 | 26,816 | 13,408,000,000,000 |
| open at knee | 89,287 | 1.0 | 89,287 | 44,643,500,000,000 |
| advance 1x | 210,689 | 2.0 | 105,344 | 52,672,250,000,000 |
| advance 2x | 210,689 | 4.0 | 52,672 | 26,336,125,000,000 |
| advance 4x | 210,689 | 8.0 | 26,336 | 13,168,062,500,000 |
| advance 6x | 210,689 | 12.0 | **17,557** | **8,778,708,333,333** |

**The binding (lowest) ceiling is the advance leg at the 6x stall peak: `BOUNTY_ETH_TARGET ≤
8,778,708,333,333 wei` to keep round-trip ≤ 0 on EVERY leg at the 0.5 gwei reference.** (The buy
leg's 12.66e12 ceiling binds among the non-escalated legs; the 6x advance is tighter only because the
12x multiplier stacks on the advance ratio — see §4 for why a one-shot 6x is not a self-crank faucet.)

**Current fixture `BOUNTY_ETH_TARGET = 885,000,000` wei is ~14,000x BELOW even the tightest (6x)
ceiling.** At the current value, EVERY leg is round-trip ≤ 0 at the 0.5 gwei reference AND deeply
negative at any market price (proof, reward ETH-equiv vs cost):

| Price | buy (1.5xB=1.33e9) vs cost | open (1.0xB=885e6) vs cost | advance 6x (12xB=10.62e9) vs cost |
|-------|----------------------------|----------------------------|-----------------------------------|
| 0.5 gwei (ref) | 1.33e9 < 20.11e12 ✓ | 885e6 < 44.64e12 ✓ | 10.62e9 < 105.34e12 ✓ |
| 1 gwei | 1.33e9 < 40.22e12 ✓ | 885e6 < 89.29e12 ✓ | 10.62e9 < 210.69e12 ✓ |
| 5 gwei | 1.33e9 < 201.12e12 ✓ | 885e6 < 446.44e12 ✓ | 10.62e9 < 1,053.4e12 ✓ |
| 50 gwei | 1.33e9 < 2,011.2e12 ✓ | 885e6 < 4,464.4e12 ✓ | 10.62e9 < 10,534.5e12 ✓ |

So the fixture value is NOT a faucet risk; like 319, it is ~14,000x below the keeper's actual gas
cost and therefore *under*-incentivizes the keeper. The fix is an economic deploy choice, NOT a
frozen-constant edit (§5).

---

## 4. The 6x-stall over-reimbursement is a ONE-SHOT, not a self-crank faucet (T-331-10)

If `BOUNTY_ETH_TARGET` were pegged so the BUY leg breaks even exactly at the 0.5 gwei reference
(`B = 13,408,000,000,000` wei), the advance leg at the 6x peak would over-reimburse by ~1.53x AT THE
0.5 gwei REFERENCE (reward 160.9e12 vs cost 105.3e12). That looks like a faucet — but it is not a
repeatable one, for three structural reasons:

1. **Advance is ONE rewardable call per day-advance.** Once `advanceGame()` moves the day,
   `advanceDue()` returns false (`DegenerusGame.sol:1623-1639`), so the leg cannot be re-cranked. The
   next rewardable advance is ≥1 game-day away. There is no loop to amplify.
2. **The 6x only exists after a REAL ≥2-hour stall** (`AdvanceModule.sol:235-241`: `mult=6` at
   `elapsed >= 2 hours`). A self-cranker cannot manufacture a 6x on demand — it requires that NOBODY
   advanced the game for 2 hours (a genuine liveness emergency the bounty is designed to pay extra to
   resolve). The escalation is ADVANCE-ONLY (the autoBuy stall ladder was deleted per D-07; advance
   is the sole stall epoch — invariant (d) satisfied-by-deletion).
3. **The exploitability judgement is REAL gas, not the 0.5 gwei reference** (`feedback_bounty_exploit_uses_real_gas_not_peg_ref`).
   A 2-hour mainnet stall plausibly coincides with HIGH gas / congestion, not 0.5 gwei. At any market
   price ≥ 1 gwei the 6x advance reward is < cost even at a buy-pegged B (@1 gwei: 160.9e12 reward <
   210.7e12 cost). The flip-credit is illiquid coinflip stake, not liquid ETH.

**Stall-ceiling decision (GAS-04): KEEP the 1/2/4/6 ladder ADVANCE-ONLY; NO ceiling extension above
the 2-hour tier.** Rationale derived from the GAS data:
- 6x (12x `unit`) over-reimburses the advance marginal by 1.53x at the 0.5 gwei *reference* and is a
  ONE-SHOT (not loopable). At the realistic ≥1 gwei market floor it is already round-trip ≤ 0.
- A ceiling extension (e.g. an 8x/10x tier above 2h) would only be justified if 6x failed to cover
  the advance gas at stressed mainnet gas — it does not need to: even at 50 gwei the advance 6x at the
  current fixture B is round-trip ≤ 0 by 3 orders of magnitude, and a USER-tuned production B (§5)
  would be capped against the finite faucet pool. Adding a higher tier would push the reference-price
  over-reimbursement higher (toward an actual faucet at any B chosen to incentivize the base leg)
  with no liveness benefit (a keeper who will advance at 6x will advance at 6x; the day still moves
  on the first call regardless of the tier).
- **Faucet-pool cap (if the USER ever extends):** any tier added ABOVE 2h must be capped so the
  per-call reward at the new top multiplier stays below `BOUNTY_ETH_TARGET_production * top_mult`
  reimbursed against the advance marginal at the ≥1 gwei market floor, AND the cumulative bounty
  emission stays within the finite flip-credit faucet pool (the bounty is minted flip-credit, so the
  "pool" is the protocol's tolerance for outstanding illiquid credit, not an ETH balance). Existing
  thresholds (20 min / 1 h / 2 h → 2 / 4 / 6) are NEVER lowered.

**Decision: NO EXTENSION.** The 1/2/4/6 ADVANCE-ONLY ladder is confirmed; the one-shot 6x
over-reimbursement at the 0.5 gwei reference is structurally bounded (not loopable, real-gas safe) and
needs no higher tier.

---

## 5. `BOUNTY_ETH_TARGET` deploy-param recommendation (SURFACED-NOT-GATED)

`BOUNTY_ETH_TARGET` is an AfKing constructor immutable (`AfKing.sol:261`, set `:277`), supplied by the
deploy script. The test fixture is `DeployProtocol.sol:126` = `885_000_000` wei (the same value 319
carried). The per-call bounty ETH-equivalent recovers to `ratio * BOUNTY_ETH_TARGET` wei at every
mintPrice level (mp cancels — §6).

**Recommended PRODUCTION ceiling (the hard faucet floor):**

| Lens | Ceiling on `BOUNTY_ETH_TARGET` |
|------|--------------------------------|
| Round-trip ≤ 0 at the 0.5 gwei REFERENCE on EVERY leg incl. the 6x advance peak | `≤ 8,778,708,333,333 wei` (the advance-6x bind, §3) |
| Round-trip ≤ 0 at the 0.5 gwei REFERENCE on the buy leg (the binding non-escalated leg) | `≤ 12,662,000,000,000 wei` (buy clean N32) |
| Round-trip ≤ 0 at the ≥1 gwei MARKET floor (the realistic SAFE standard, 2x cushion) on the buy leg | `≤ 25,324,000,000,000 wei` (buy clean N32, 1 gwei) |

**Decision: NO autonomous deploy-param change; SURFACE for the USER (Task-gate item).** Rationale
(identical to the 319 disposition):
1. `BOUNTY_ETH_TARGET` is an ECONOMIC / keeper-incentive parameter, not a pure gas-floor constant.
   Setting it correctly trades off (a) keeper incentive — it must at least approach the keeper's
   market gas cost or no third party runs the router — against (b) the self-crank faucet ceiling at
   the 6x advance peak. The faucet ceiling is the GAS deliverable (above); the incentive target (how
   close to gas cost to pay) is the USER's economic choice.
2. `DeployProtocol.sol:126` is a TEST FIXTURE value. The PRODUCTION keeper deploy lives in the paired
   `degenerus-utilities` repo, so the fixture arg is not the mainnet value. Changing the fixture
   would only affect test economics.
3. The recommended hard CEILING is **`BOUNTY_ETH_TARGET ≤ 8,778,708,333,333 wei`** (the advance-6x,
   0.5 gwei-reference, round-trip ≤ 0 bound — the strictest of the three lenses). A production value
   that under-shoots this (e.g. anywhere in the ~`5e12`–`8.7e12` band) reimburses a meaningful
   fraction of the keeper's ≥1 gwei market gas on the base leg while keeping the 6x peak round-trip ≤
   0 at the reference. The current fixture `885,000,000` is ~14,000x below this — safe but
   under-incentivizing.

**No `DeployProtocol.sol` edit is proposed here.** If the USER wants the production target tuned, that
is a separate AGENT-editable deploy-param change in the `degenerus-utilities` repo (not part of the
frozen 331-05 gate).

---

## 6. Level-invariance proof (GAS-04)

The unit conversion is `unit = (BOUNTY_ETH_TARGET * PRICE_COIN_UNIT) / mp` with
`PRICE_COIN_UNIT = 1000 ether` (`AfKing.sol:233, 870`). Each leg's reward is `ratio * unit` BURNIE-wei.
Valuing the BURNIE reward back to ETH multiplies by `mp / PRICE_COIN_UNIT` (the inverse conversion),
so the ETH-equivalent of any leg's reward is:

```
ETH_equiv = ratio * unit * mp / PRICE_COIN_UNIT
          = ratio * (BOUNTY_ETH_TARGET * PRICE_COIN_UNIT / mp) * mp / PRICE_COIN_UNIT
          = ratio * BOUNTY_ETH_TARGET                          // mp CANCELS
```

`mp` cancels exactly — the ETH-equivalent break-even reward is `ratio * BOUNTY_ETH_TARGET` wei at
EVERY mintPrice level. Worked across ≥2 levels at `B = 885,000,000` wei (exact integer arithmetic,
the same floor-division the EVM does):

| Level (price) | mp (wei) | `unit = B*1000e18/mp` (BURNIE-wei) | ETH-equiv `= unit*mp/1000e18` (wei) | == B? |
|---------------|----------|------------------------------------|--------------------------------------|-------|
| 0–4 (0.01 ETH) | 1e16 | 88,500,000,000,000 | 885,000,000 | YES |
| 30–59 (0.08 ETH) | 8e16 | 11,062,500,000,000 | 885,000,000 | YES |
| milestone (0.24 ETH) | 24e16 | 3,687,500,000,000 | 885,000,000 | YES |

The reward's ETH value is invariant across the full `priceForLevel` ladder
(`PriceLookupLib.sol:21-66`: 0.01 / 0.02 / 0.04 / 0.08 / 0.12 / 0.16 / 0.24 ETH). The integer
floor-division introduces at most sub-wei truncation, far below the gwei-scale faucet floor.

> The EMPIRICAL level-invariance assertion (the `SweepPerPlayerWorstCaseGas.t.sol:188-211`
> shape-insensitivity idiom — reward equal across ≥2 levels within tolerance) is proven at TST Phase
> 332 (TST-04 reward-routing). This record proves the ARITHMETIC invariance; 332 proves it on-chain.

---

## 7. `RESOLVE_FLAT_BURNIE` (GAS-06) — confirm `1e18`, the anti-exploit basis is the bet-stake gate

`RESOLVE_FLAT_BURNIE = 1e18` (`DegenerusGame.sol:1543`) is a flat ~1-BURNIE flip-credit paid ONCE per
tx at `successCount >= 3` non-WWXRP resolutions (`:1620`); `totalResolved == 0` reverts `NoWork()`
(`:1619`); 1–2 resolved commit UNPAID (never strand the trailing tail). WWXRP (currency == 3) resolves
but never counts toward the gate (AUTO-04, `:1600-1609`). This is a count-independent flat literal —
NOT a per-item marginal peg (it is paid once regardless of N), so the CR-01 N≥32 rule does not apply;
the calibration is a sub-real-gas sanity check, NOT a break-even derivation.

**1 BURNIE flip-credit ETH-value** = `RESOLVE_FLAT_BURNIE * mp / PRICE_COIN_UNIT = mp / 1000`:
- level 0–4 (0.01 ETH mp): 1 BURNIE = 10,000,000,000,000 wei (0.000010 ETH)
- milestone (0.24 ETH mp): 1 BURNIE = 240,000,000,000,000 wei (0.000240 ETH)

**Real 3-resolution tx gas** (the gate minimum) ≈ `3 * 66,528` = 199,584 gas (the 319 per-resolve
marginal, used as a conservative LOW estimate). Round-trip (reward ETH-equiv vs real gas cost):

| Corner | reward (wei) | 3-resolve cost (wei) | round-trip |
|--------|--------------|----------------------|------------|
| low mp (0.01 ETH) @ 0.5 gwei | 10.0e12 | 99.79e12 | NEG (safe) |
| low mp @ 50 gwei | 10.0e12 | 9,979e12 | NEG (safe) |
| **milestone (0.24 ETH) @ 0.5 gwei** | **240e12** | **99.79e12** | **POS at the reference** |
| milestone @ 1 gwei | 240e12 | 199.58e12 | POS (marginal) |
| milestone @ 2 gwei | 240e12 | 399.17e12 | NEG (safe) |
| milestone @ ≥5 gwei | 240e12 | ≥997.9e12 | NEG (safe) |

There IS a narrow reference-price corner (milestone mintPrice + sub-2-gwei gas + exactly-3-resolve)
where the 1-BURNIE reward exceeds the bare resolve gas. **It is structurally mitigated and `1e18` is
confirmed (no change)** for three reasons:

1. **The bet-stake gate dominates the round-trip (the decisive D-05 anti-exploit basis).** To harvest
   the 1-BURNIE the farmer must FIRST place ≥3 Degenerette bets (real -EV stake at the house edge),
   and resolving a LOSING bet returns nothing. The round-trip is `1 BURNIE − (3-bet stake + resolve
   gas)`, dominated by the bet stake — net deeply negative. The reward is a "lose" consolation, not a
   gas-reimbursement peg, so it is intentionally NOT pegged to the resolve marginal.
2. **WWXRP is excluded from the gate** (AUTO-04), so the farmer cannot use the cheapest/most-favorable
   bet shape to manufacture the 3 counts.
3. **The hot corner is implausible:** mp = 0.24 ETH only at game level 100/200/… (≥100 days of
   sustained play), and 0.5 gwei is below the realistic ≥1 gwei mainnet floor. At any market price ≥
   2 gwei even the bare resolve gas exceeds the reward, before the bet stake is counted.

> SPEC D-05f already verified no invariant requires losing-bet resolution before dropping the
> break-even incentive. If a realistic corner ever flipped positive on the bet-stake-inclusive
> round-trip, the lever is to LOWER `RESOLVE_FLAT_BURNIE` (e.g. ≤ ~0.42 BURNIE keeps the milestone +
> 0.5 gwei + 3-resolve corner sub-bare-gas) or add a scaled gate — but neither is needed: the
> bet-stake gate already makes every realistic farm net-negative. **Confirm `1e18`.**

---

## 8. Per-constant decision summary (the exact 331-05 diff)

| Constant | File:line (`63bc16ca`) | Measured input | Current | **Proposed** | Decision | Faucet floor |
|----------|------------------------|----------------|---------|--------------|----------|--------------|
| `DOWORK_BATCH`      | `AfKing.sol:847` | whole-leg worst case << 30M at N=100 (buy 1.29M / open 2.86M, 331-GAS-DERIVATION §5) | `100` | **`100` (UNCHANGED)** | CONFIRM — per-leg default batch; worst-case per-tx at N=100 is far under 30M | n/a (anti-DoS cap, not a reward) |
| `ADVANCE_RATIO_NUM` | `AfKing.sol:849` | advance base 210,689 gas (5.24x buy); 2x base + 1/2/4/6 ladder | `2` | **`2` (UNCHANGED)** | CONFIRM — base ratio; the stall ladder is the escalation lever (§4) | 6x peak round-trip ≤ 0 at fixture B; one-shot (§4) |
| `BUY_RATIO_NUM` / `BUY_RATIO_DEN` | `AfKing.sol:851-852` | buy 40,224 gas (cheapest, highest-priority leg) | `3` / `2` | **`3` / `2` (UNCHANGED)** | CONFIRM — flat 1.5x; richest ratio for the cheapest, liveness-critical leg | binding non-escalated ceiling 12.66e12 wei (§3) |
| `OPEN_KNEE`         | `AfKing.sol:854` | open 89,287 gas; the small-batch corner closer | `5` | **`5` (UNCHANGED)** | CONFIRM — `1x * min(opened,5)/5`; a 1-box open earns 0.2x → −EV (§3) | open at knee round-trip ≤ 0; k<5 deeply −EV |
| `RESOLVE_FLAT_BURNIE` | `DegenerusGame.sol:1543` | flat ~1-BURNIE; bet-stake gate dominates (§7) | `1e18` | **`1e18` (UNCHANGED)** | CONFIRM — count-independent "lose" reward; bet-stake gate makes every farm net-negative | sub-real-gas at ≥2 gwei; bet-stake gate the binding floor (§7) |
| `BOUNTY_ETH_TARGET` | `AfKing.sol:261` (deploy-param) | binding ceiling 8,778,708,333,333 wei (advance-6x @ref) | `885_000_000` (fixture) | **SURFACED — no autonomous change** | SURFACE — recommend production `≤ 8.78e12` wei; current ~14,000x below (under-incentivizes, not a faucet) | n/a (economic choice; ceiling in §5) |

**Disposition: the five frozen `AfKing.sol` constants + `RESOLVE_FLAT_BURNIE` are all CONFIRMED at
their current placeholder values** — the measured marginals support `100 / 2 / 3,2 / 5` and the
bet-stake gate supports `1e18`. The 331-05 frozen-contract diff is therefore **EMPTY of value changes
to the gated constants** (the placeholders were chosen correctly by the 330 IMPL); 331-05's only
gated action is to STRIKE the `GAS-331 PLACEHOLDER` comment markers (the values are now calibrated and
final). `BOUNTY_ETH_TARGET` is surfaced for the USER as a deploy-param economic choice.

### The exact 331-05 diff (for the USER-APPROVED gate — NOT applied here)

```diff
--- a/contracts/AfKing.sol
+++ b/contracts/AfKing.sol
@@ -845,11 +845,12 @@
-    /// @dev GAS-331 PLACEHOLDER — fixed per-leg default batch (the prior caller-bounded
-    ///      default). Calibrated under the USER-gated GAS phase (331), NOT locked here.
+    /// @dev Fixed per-leg default batch. Calibrated GAS-331: worst-case per-tx at N=100
+    ///      (buy 1.29M / open 2.86M gas) is far under the 30M mainnet block bar.
     uint256 internal constant DOWORK_BATCH = 100;
-    /// @dev GAS-331 PLACEHOLDER — advance reward ratio (2x * mult). Calibrated at GAS (331).
+    /// @dev Advance reward ratio (2x * mult). Calibrated GAS-331 to the advance base marginal;
+    ///      the 1/2/4/6 stall ladder is the escalation lever, faucet-bounded (advance-only).
     uint256 internal constant ADVANCE_RATIO_NUM = 2;
-    /// @dev GAS-331 PLACEHOLDER — buy reward ratio (flat 1.5x per tx = NUM/DEN). At GAS (331).
+    /// @dev Buy reward ratio (flat 1.5x per tx = NUM/DEN). Calibrated GAS-331 — the richest
+    ///      ratio for the cheapest-gas, highest-priority liveness leg.
     uint256 internal constant BUY_RATIO_NUM = 3;
     uint256 internal constant BUY_RATIO_DEN = 2;
-    /// @dev GAS-331 PLACEHOLDER — open reward pro-rate knee (1x at/above, pro-rated below).
+    /// @dev Open reward pro-rate knee (1x at/above, pro-rated below). Calibrated GAS-331 —
+    ///      a 1-box mid-day open earns 0.2x, below a one-box tx's gas (small-batch −EV).
     uint256 internal constant OPEN_KNEE = 5;
```

```diff
--- a/contracts/DegenerusGame.sol
+++ b/contracts/DegenerusGame.sol
@@ -1540,4 +1540,4 @@
-    /// @dev Flat ~1-BURNIE "lose" reward for the Degenerette resolve helper, paid ONCE per tx
-    ///      at >=3 non-WWXRP resolutions (D-05b). GAS-331 PLACEHOLDER — the exact value is
-    ///      calibrated under the USER-gated GAS phase (331), NOT locked here.
+    /// @dev Flat ~1-BURNIE "lose" reward for the Degenerette resolve helper, paid ONCE per tx
+    ///      at >=3 non-WWXRP resolutions (D-05b). Calibrated GAS-331: count-independent flat
+    ///      consolation; the bet-stake gate makes every self-resolve farm net-negative.
     uint256 private constant RESOLVE_FLAT_BURNIE = 1e18;
```

**No `DeployProtocol.sol` change is proposed** (`BOUNTY_ETH_TARGET` is surfaced for the USER as a
deploy-param economic choice, not autonomously tuned — §5). The comment-only edits keep the values
byte-identical, so the 331-05 diff carries ZERO behavioral change to the gated constants — it only
strikes the now-resolved `GAS-331 PLACEHOLDER` markers. **The values themselves are CONFIRMED and need
no change.**

> **331-05 gate note:** because the five frozen constants + `RESOLVE_FLAT_BURNIE` keep their exact
> literal values, the only frozen-contract mutation is the comment update. If the USER prefers to
> leave the `GAS-331 PLACEHOLDER` markers in place (treating this record as the calibration
> attestation), 331-05 may be a NO-OP on `contracts/*.sol` entirely — the calibration is fully
> recorded here either way. Test mirrors that reference these constants
> (`AfKingSubscription.t.sol`, `SweepPerPlayerWorstCaseGas.t.sol`, `CrankLeversAndPacking.t.sol`,
> `CrankFaucetResistance.t.sol`) stay GREEN because no literal value changes (no mirror sync needed,
> unlike the 319 OUTCOME-B value edits).

---

## 9. Summary for the 331-05 gate

| Item | Decision |
|------|----------|
| `DOWORK_BATCH` (`AfKing.sol:847`) | **CONFIRM `100`** — worst-case per-tx at N=100 far under 30M |
| `ADVANCE_RATIO_NUM` (`AfKing.sol:849`) | **CONFIRM `2`** — base ratio; 1/2/4/6 ladder is the escalation lever (one-shot, advance-only) |
| `BUY_RATIO_NUM` / `BUY_RATIO_DEN` (`AfKing.sol:851-852`) | **CONFIRM `3` / `2`** — flat 1.5x; binding non-escalated ceiling 12.66e12 wei |
| `OPEN_KNEE` (`AfKing.sol:854`) | **CONFIRM `5`** — 1-box open = 0.2x, small-batch −EV |
| `RESOLVE_FLAT_BURNIE` (`DegenerusGame.sol:1543`) | **CONFIRM `1e18`** — bet-stake gate dominates; sub-real-gas at ≥2 gwei |
| `BOUNTY_ETH_TARGET` deploy-param | **SURFACED — no autonomous change**; recommended production ceiling `≤ 8,778,708,333,333 wei` (advance-6x @0.5gwei ref); current fixture `885,000,000` is ~14,000x below (under-incentivizes, not a faucet) |
| CR-01 (per-item MARGINAL, never a single-item total) | **HELD** — every value derived from the N≥32 converged marginal; round-trip ≤ 0 on every leg at the 0.5 gwei reference |
| Level-invariance (GAS-04) | **PROVEN arithmetically** (mp cancels; ETH-equiv = ratio × `BOUNTY_ETH_TARGET` at every level); empirical assert at TST 332 |
| Stall-ceiling (GAS-04) | **1/2/4/6 ADVANCE-ONLY confirmed; NO EXTENSION** — 6x is a one-shot, real-gas safe; any future tier faucet-pool-capped and never lowers existing thresholds |
| Exploitability lens | **REAL prevailing gas (5–50+ gwei) + flip-credit illiquidity**, NOT the 0.5 gwei reference (`feedback_bounty_exploit_uses_real_gas_not_peg_ref`) |
| Contract approval | **REQUIRED at 331-05 — nothing pre-approved.** This plan touches NO `contracts/*.sol`; the diff above is comment-only (values byte-identical) or a clean NO-OP |
