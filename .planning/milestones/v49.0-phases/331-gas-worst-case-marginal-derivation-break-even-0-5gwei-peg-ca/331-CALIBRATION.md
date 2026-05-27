# Phase 331 — GAS-02 + GAS-04 Calibration Decision Record

**Authored:** 2026-05-27
**Contract HEAD:** `63bc16ca` (`contracts/` clean on disk this session; every cited `file:line` source-verified against the live tree — the 330 IMPL shifted lines/slots, so the line numbers below were re-read, NOT trusted from stale planning docs).
**Plan:** 331-04 — compute the calibration; **NO `contracts/*.sol` edit in this plan.** The constant landing is the SEPARATE `autonomous: false` USER-gated 331-05 diff (the v46 Phase 319 precedent `e4014f91`/`795e679d`).
**Calibration input:** `331-GAS-DERIVATION.md` §5 (the 331-01 measured worst-case marginals at N≥32, the converged column).
**Methodology floor (HARD):** `feedback_security_over_gas` (the self-crank round-trip ≤ 0 faucet floor is a hard invariant) + the CR-01 rule (peg the per-item MARGINAL, never a single-item total) + `feedback_bounty_exploit_uses_real_gas_not_peg_ref` (exploitability judged at REAL prevailing gas, not the 0.5 gwei reference).
**Analog:** `.planning/milestones/v46.0-phases/319-.../319-GAS-06-CALIBRATION.md` + `319-CR01-FIX.md` — this is the same derive→peg pass one phase up for the v49 keeper router.

> ### ⚠️ CORRECTION PASS (2026-05-27) — the BUY marginal that fed §2/§3 was WRONG
> The 331-01 marginals this record consumed had a load-bearing error (see `331-GAS-DERIVATION.md` §0
> banner): the BUY per-player marginal was measured on the REVERT-CATCH path (`40,224`), not a real
> landing buy. The CORRECTED buy marginal is **~261,809** (clean N32 ~255,614) — an order of magnitude
> higher. Consequences re-worked below:
> - **§2 relative-marginal analysis:** buy is now the MOST expensive per-item leg (~262k > advance
>   210k > open 89k), INVERTING the original "buy cheapest → richest 1.5x" justification. Re-examined
>   in §2 + the new §2.1.
> - **§3 faucet-floor table:** the buy-leg `BOUNTY_ETH_TARGET` ceiling RISES with the higher marginal
>   (a more expensive leg can be reimbursed more before round-trip flips positive), so the buy leg is
>   now LESS binding. The advance-6x ceiling (`8.78e12 wei`) REMAINS the overall binding faucet floor
>   — confirmed in the corrected §3.
> - **The ratio VALUES (1.5/1.0/2.0, knee=5) are FROZEN and out of scope** — this pass re-verifies they
>   still avoid a faucet at the current `BOUNTY_ETH_TARGET` (they do) and FLAGS the buy
>   under-reimbursement implication; it does NOT re-propose them.
> - **The single `DOWORK_BATCH=100` is recommended SPLIT into `BUY_BATCH=50` + `OPEN_BATCH=100`**
>   (sizing in `331-GAS-DERIVATION.md` §5.1). This changes the §8 diff from comment-only to a real
>   (still gated) edit. The §8 table is updated accordingly.

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

**The CORRECTED measured marginals (331-GAS-DERIVATION.md §5, N≥32 converged column):**

| Calibration input | Measured gas | N | Source |
|-------------------|--------------|---|--------|
| `router_dowork_buy_per_player_marginal_gas`  | **261,809** (clean N32 255,614) | 32 | 331-GAS-DERIVATION §1/§5 |
| `router_dowork_open_per_box_marginal_gas` (TYPICAL) | **89,288** (clean N32 85,967) | 32 | 331-GAS-DERIVATION §2/§5 |
| `router_dowork_open_whale_pass_box_marginal_gas` (RARE WORST CASE) | **5,396,350** | 1 | 331-GAS-DERIVATION §2/§5 |
| `router_dowork_advance_marginal_gas`         | **210,689** (base, mult=1; single step) | 1 | 331-GAS-DERIVATION §3/§5 |
| `router_dowork_dispatch_overhead_gas`        | **568,870** (conservative ceiling, REAL landing buy) | 1 | 331-GAS-DERIVATION §4/§5 |

**CR-01 rule (the load-bearing lesson from 319):** the per-item flat reward MUST be pegged to the
per-item MARGINAL at N≥32 — never a single-item TOTAL. At 319 the box reward was over-pegged ~2x by
using the single-box total (137,944) instead of the per-box marginal (~71,203), opening a Sybil
self-crank faucet on the multi-box path. The CORRECTED gradient (every buy LANDS): buy
N1=484,194→N32=255,614 ~1.89x; open N1=180,221→N32=85,967 ~2.10x. **Every value below is derived
from the N≥32 converged marginal.**

**Anti-exploit basis is REAL prevailing gas, NOT the 0.5 gwei reference** (`feedback_bounty_exploit_uses_real_gas_not_peg_ref`,
which the USER corrected twice in Phase 329). The 0.5 gwei reference fixes the break-even peg; the
faucet judgement values the keeper's real tx cost at 5–50+ gwei against the illiquid flip-credit
reward valued at the 0.5 gwei peg. Both framings are stated for every constant below.

---

## 1. What is actually GATED vs SURFACED (the calibration-target distinction)

| Symbol | File:line (verified `63bc16ca`) | Kind | Calibration disposition |
|--------|----------------------------------|------|--------------------------|
| `DOWORK_BATCH`      | `AfKing.sol:847` | frozen `internal constant` | **GATED — CHANGE (correction):** SPLIT into `BUY_BATCH = 50` + `OPEN_BATCH = 100` (331-GAS-DERIVATION §5.1); buy at 100 = ~26M > the 16.7M HARD ceiling |
| `ADVANCE_RATIO_NUM` | `AfKing.sol:849` | frozen `internal constant` | **GATED** — confirm `2` |
| `BUY_RATIO_NUM`     | `AfKing.sol:851` | frozen `internal constant` | **GATED** — confirm `3` (frozen ratio; buy is now the most expensive leg but the value is out of scope — §2.1) |
| `BUY_RATIO_DEN`     | `AfKing.sol:852` | frozen `internal constant` | **GATED** — confirm `2` |
| `OPEN_KNEE`         | `AfKing.sol:854` | frozen `internal constant` | **GATED** — confirm `5` |
| `RESOLVE_FLAT_BURNIE` | `DegenerusGame.sol:1543` | frozen `private constant` | **GATED** — confirm `1e18` |
| `BOUNTY_ETH_TARGET` | `AfKing.sol:261` (immutable, set `:277` from ctor arg `_bountyEthTarget`; fixture `DeployProtocol.sol:126` = `885_000_000`) | **deploy-param immutable** | **SURFACED-NOT-GATED** — recommend a faucet ceiling + flag the buy-incentive-vs-faucet tension (§5); the production value is a USER economic choice in the paired `degenerus-utilities` deploy script |

> **Correction note:** the original record had `DOWORK_BATCH` as **CONFIRM `100`**. The corrected buy
> marginal (~262k) makes a 100-deep buy batch ~26M, over the 16.7M HARD ceiling, so the single batch
> constant is split (buy 50 / open 100). This is a BEHAVIORAL change behind the same 331-05 gate.

The five `AfKing.sol` `internal constant`s + `RESOLVE_FLAT_BURNIE` are frozen `contracts/*.sol`
literals → they are behind the USER-APPROVED 331-05 gate. `BOUNTY_ETH_TARGET` is a constructor
immutable supplied by the deploy script (AGENT-editable, NOT a frozen constant) — surfaced for the
USER exactly as 319 did with the same parameter.

---

## 2. The ratio constants encode the RELATIVE per-category marginals (a single shared `unit`) — CORRECTED

A flat-per-tx model with ONE shared `unit` and per-category ratios can reimburse exactly ONE leg at
break-even; the other legs are deliberately UNDER-reimbursed (the anti-faucet margin). The CORRECTED
measured relative marginals (normalized to open = 1.0, since buy is no longer the smallest):

| Leg | Marginal gas | Relative to open | Current reward ratio (x `unit`) |
|-----|--------------|------------------|----------------------------------|
| open at knee (typical) | 89,288  | 1.00  | **1.0x** (`5/5`) |
| advance base  | 210,689 | 2.36  | **2.0x** (`2 * mult`, base mult=1) |
| buy (LANDING) | 261,809 | 2.93  | **1.5x** (`3/2`) |

**CORRECTION — the original "buy cheapest → richest 1.5x" justification is INVERTED.** With the buy
marginal corrected from ~40k to ~262k, BUY is now the MOST expensive per-item leg (above even advance
base), yet it carries only a 1.5x ratio. So the model does NOT pay the most expensive leg the richest
ratio — buy is now the most UNDER-reimbursed leg relative to its gas. This is examined in §2.1.

The ratios are NOT a 1:1 mirror of the relative marginals, and (post-correction) that is even more
deliberately the case — the model is a SINGLE shared `unit` (not three independent pegs). The relevant
invariant remains the per-leg break-even: **each leg's reward, valued at the peg, must be AT or BELOW
that leg's real marginal at the 0.5 gwei reference (round-trip ≤ 0).** §3 proves a single shared
`BOUNTY_ETH_TARGET` keeps all legs simultaneously at/below their marginal — and the correction makes
the buy leg MORE comfortably under-reimbursed, not less.

**The ratio VALUES are FROZEN (329 SPEC D-07; out of scope for calibration).** This pass does NOT
re-propose them. It re-verifies (§3) they still avoid a faucet at the current `BOUNTY_ETH_TARGET` —
they do — and FLAGS the buy under-reimbursement (§2.1).

---

## 2.1 BUY UNDER-REIMBURSEMENT — the corrected keeper-incentive implication (FLAG, not a change)

With buy the most expensive leg (~262k) and the cheapest reward ratio relative to gas (1.5x vs the
2.36x its gas would proportionally warrant against open's 1.0x), the buy leg is the leg a keeper is
LEAST compensated for, per unit gas. At the current fixture `BOUNTY_ETH_TARGET = 885,000,000` wei the
buy reward ETH-equiv is `1.5 * 885e6 = 1.33e9` wei, against a real buy cost of `261,809 * price`:

| Price | buy reward ETH-equiv | buy real cost | keeper net on the buy leg |
|-------|----------------------|---------------|---------------------------|
| 0.5 gwei (ref) | 1.33e9 | 130.9e12 | −130.9e12 (deeply −) |
| 1 gwei | 1.33e9 | 261.8e12 | −261.8e12 |
| 5 gwei | 1.33e9 | 1,309e12 | −1,309e12 |

**Implication (FLAGGED for the USER, not auto-changed):** at the current fixture `BOUNTY_ETH_TARGET`,
the buy leg — the highest-priority daily-liveness leg — reimburses ~0.001% of the keeper's real gas.
This is consistent with the §5 finding that the fixture B is ~14,000x below the faucet ceiling and
broadly UNDER-incentivizes the keeper; the buy leg is simply the most under-incentivized of the three.
If the USER tunes the production `BOUNTY_ETH_TARGET` upward toward keeper-incentive viability (the
deploy-param economic choice, §5), the BUY leg is the binding incentive consideration (it must clear
~262k×market-gas to make a keeper run the daily buy), while the advance-6x peak remains the binding
FAUCET ceiling (§3). The two pull in opposite directions — the USER's production B should sit in the
band that incentivizes the ~262k buy at the realistic market floor while keeping the 6x advance peak
round-trip ≤ 0 at the 0.5 gwei reference. **The ratio constants are not the lever here; `BOUNTY_ETH_TARGET`
is (and it is surfaced, not gated).**

---

## 3. Faucet-floor analysis — the per-leg round-trip ≤ 0 proof

Reward credited per leg, valued back at the peg, recovers exactly `ratio * BOUNTY_ETH_TARGET` ETH (mp
cancels — §6). The keeper's REAL cost is `marginal_gas * (real gas price)`. Round-trip ≤ 0 ⟺
`ratio * BOUNTY_ETH_TARGET ≤ marginal_gas * (price)`. Rearranged, the per-leg ceiling on the shared
deploy-param at the 0.5 gwei reference is `BOUNTY_ETH_TARGET ≤ marginal_gas * 0.5gwei / ratio`:

| Leg | marginal_gas (CORRECTED) | ratio | `marginal/ratio` (gas-equiv) | Ceiling on `BOUNTY_ETH_TARGET` @0.5gwei ref (wei) |
|-----|--------------------------|-------|------------------------------|---------------------------------------------------|
| open at knee | 89,288 | 1.0 | **89,288** | **44,644,000,000,000** |
| buy (clean N32) | 255,614  | 1.5  | 170,409 | 85,204,666,666,666 |
| buy (conservative N32) | 261,809 | 1.5 | 174,539 | 87,269,666,666,666 |
| advance 1x | 210,689 | 2.0 | 105,344 | 52,672,250,000,000 |
| advance 2x | 210,689 | 4.0 | 52,672 | 26,336,125,000,000 |
| advance 4x | 210,689 | 8.0 | 26,336 | 13,168,062,500,000 |
| advance 6x | 210,689 | 12.0 | **17,557** | **8,778,708,333,333** |

**The binding (lowest) ceiling is STILL the advance leg at the 6x stall peak: `BOUNTY_ETH_TARGET ≤
8,778,708,333,333 wei` to keep round-trip ≤ 0 on EVERY leg at the 0.5 gwei reference.** CORRECTION
EFFECT: the buy-leg ceiling ROSE from ~12.66e12 (at the wrong 37,986 marginal) to ~85.2e12 (at the
corrected 255,614) — a more expensive leg can absorb a larger `BOUNTY_ETH_TARGET` before its
round-trip flips positive, so the buy leg is now FAR from binding. The NON-escalated binding ceiling
is now the OPEN leg (~44.64e12, the cheapest per-item leg at a 1.0x ratio). The advance-6x peak
(8.78e12) remains the overall faucet floor because the 12x multiplier stacks on the advance ratio —
see §4 for why a one-shot 6x is not a self-crank faucet. **The buy correction makes the buy faucet
ceiling LESS binding, exactly as predicted; the overall bind is unchanged.**

**Current fixture `BOUNTY_ETH_TARGET = 885,000,000` wei is ~14,000x BELOW even the tightest (6x)
ceiling.** At the current value, EVERY leg is round-trip ≤ 0 at the 0.5 gwei reference AND deeply
negative at any market price (proof, reward ETH-equiv vs cost):

| Price | buy (1.5xB=1.33e9) vs cost (261,809×p) | open (1.0xB=885e6) vs cost (89,288×p) | advance 6x (12xB=10.62e9) vs cost (210,689×p) |
|-------|-----------------------------------------|----------------------------------------|-----------------------------------------------|
| 0.5 gwei (ref) | 1.33e9 < 130.9e12 ✓ | 885e6 < 44.64e12 ✓ | 10.62e9 < 105.34e12 ✓ |
| 1 gwei | 1.33e9 < 261.8e12 ✓ | 885e6 < 89.29e12 ✓ | 10.62e9 < 210.69e12 ✓ |
| 5 gwei | 1.33e9 < 1,309e12 ✓ | 885e6 < 446.44e12 ✓ | 10.62e9 < 1,053.4e12 ✓ |
| 50 gwei | 1.33e9 < 13,090e12 ✓ | 885e6 < 4,464.4e12 ✓ | 10.62e9 < 10,534.5e12 ✓ |

So the fixture value is NOT a faucet risk on ANY leg (the corrected, higher buy cost only WIDENS the
buy leg's negative round-trip). Like 319, the fixture B is ~14,000x below the keeper's actual gas cost
and therefore *under*-incentivizes the keeper (the buy leg most of all — §2.1). The fix is an economic
deploy choice, NOT a frozen-constant edit (§5).

---

## 4. The 6x-stall over-reimbursement is a ONE-SHOT, not a self-crank faucet (T-331-10)

CORRECTION: with the corrected buy marginal, pegging B to the BUY break-even at the 0.5 gwei reference
gives `B = 87,269,666,666,666` wei (buy conservative N32) — but that B would put the advance-6x leg
WILDLY over the faucet ceiling (advance-6x ceiling is 8.78e12, ~10x below). So a buy-pegged B is NOT a
candidate; the binding ceiling is and remains the advance-6x. The one-shot analysis below is
therefore framed at the BINDING advance-6x-pegged B. If `BOUNTY_ETH_TARGET` were pegged so the advance
leg breaks even exactly at the 6x peak at the 0.5 gwei reference (`B = 8,778,708,333,333` wei), the 6x
advance reward equals its cost AT THE REFERENCE by construction (round-trip = 0, not positive). The
historical "1.53x over-reimbursement" framing assumed a buy-pegged B that the correction has shown to
be infeasible; the relevant fact is simpler — the 6x peak is round-trip ≤ 0 at the binding-pegged B,
and even a slight over-peg of the 6x is not a repeatable faucet, for three structural reasons:

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
the 2-hour tier.** Rationale derived from the GAS data (UNCHANGED by the buy correction — advance is
the binding ceiling and the advance marginal did not change):
- 6x (12x `unit`) at a binding-pegged B is round-trip ≤ 0 at the 0.5 gwei *reference* and is a
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
| Round-trip ≤ 0 at the 0.5 gwei REFERENCE on EVERY leg incl. the 6x advance peak (the overall FAUCET floor) | `≤ 8,778,708,333,333 wei` (the advance-6x bind, §3) |
| Round-trip ≤ 0 at the 0.5 gwei REFERENCE on the OPEN leg (the binding NON-escalated leg, post-correction) | `≤ 44,644,000,000,000 wei` (open at knee) |
| Round-trip ≤ 0 at the 0.5 gwei REFERENCE on the BUY leg (now FAR from binding — corrected marginal) | `≤ 85,204,666,666,666 wei` (buy clean N32) |
| BUY keeper-incentive FLOOR at the ≥1 gwei MARKET floor (the leg a keeper is least paid for, §2.1) | `≳` a B that makes `1.5 × B ≈ 255,614 × 1 gwei` ⟹ `B ≈ 170,409,333,333 wei` for buy break-even at 1 gwei |

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
   0.5 gwei-reference, round-trip ≤ 0 bound — the strictest faucet lens). A production value that
   under-shoots this (e.g. anywhere in the ~`5e12`–`8.7e12` band) reimburses a fraction of the keeper's
   ≥1 gwei market gas on the base legs while keeping the 6x peak round-trip ≤ 0 at the reference. The
   current fixture `885,000,000` is ~14,000x below this — safe but under-incentivizing.

> **CORRECTED tension the USER must weigh (FLAG):** the corrected buy marginal (~256k) means the BUY
> keeper-incentive FLOOR (~`170e12` wei to break the buy leg even at 1 gwei market) sits ABOVE the
> advance-6x FAUCET ceiling (~`8.78e12` wei) by ~20x. The two CANNOT both be satisfied with a single
> shared `BOUNTY_ETH_TARGET`: a B large enough to incentivize the daily buy at market gas would make
> the one-shot 6x advance reference-price round-trip positive (an over-reimbursement, though §4 shows
> it is NOT a loopable faucet). This is the INHERENT cost of the single-shared-`unit` flat-per-tx
> model with frozen ratios. The faucet floor (`≤ 8.78e12`) is the HARD ceiling for self-crank safety
> at the 0.5 gwei reference; a USER who wants the buy leg actually incentivized at market gas is
> choosing to accept a reference-price 6x over-reimbursement (bounded as a one-shot, real-gas safe at
> ≥1 gwei — §4) in exchange for keeper liveness. **This trade-off is the USER's economic call; the GAS
> deliverable is the faucet ceiling + the surfaced tension, NOT a chosen B.**

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

| Constant | File:line (`63bc16ca`) | Measured input (CORRECTED) | Current | **Proposed** | Decision | Faucet floor |
|----------|------------------------|----------------------------|---------|--------------|----------|--------------|
| `DOWORK_BATCH` → `BUY_BATCH` + `OPEN_BATCH` | `AfKing.sol:847` (+ call sites `:876`/`:888`) | buy ~262k/item ⟹ 100×262k=26M > 16.7M; open ~89k/item ⟹ 100×89k=9M | `100` (single) | **SPLIT `BUY_BATCH = 50` / `OPEN_BATCH = 100`** | **CHANGE** — buy 50×262k≈13.1M < 16.7M (HARD); open 100×89k≈9M (target avg) | buy HARD ≤ 16.7M; open avg ~9M (all-whale-pass corner USER-accepted) |
| `ADVANCE_RATIO_NUM` | `AfKing.sol:849` | advance base 210,689 gas (2.36x open); 2x base + 1/2/4/6 ladder | `2` | **`2` (UNCHANGED)** | CONFIRM — base ratio; the stall ladder is the escalation lever (§4) | 6x peak round-trip ≤ 0 at fixture B; one-shot (§4) |
| `BUY_RATIO_NUM` / `BUY_RATIO_DEN` | `AfKing.sol:851-852` | buy ~261,809 gas (now the MOST expensive leg — §2.1) | `3` / `2` | **`3` / `2` (UNCHANGED — frozen ratio)** | CONFIRM-as-frozen — value out of scope; the buy is now the most UNDER-reimbursed leg, FLAGGED (§2.1) | far-from-binding ceiling 85.2e12 wei (§3) |
| `OPEN_KNEE`         | `AfKing.sol:854` | open 89,288 gas; the small-batch corner closer | `5` | **`5` (UNCHANGED)** | CONFIRM — `1x * min(opened,5)/5`; a 1-box open earns 0.2x → −EV (§3) | open at knee round-trip ≤ 0; k<5 deeply −EV |
| `RESOLVE_FLAT_BURNIE` | `DegenerusGame.sol:1543` | flat ~1-BURNIE; bet-stake gate dominates (§7) | `1e18` | **`1e18` (UNCHANGED)** | CONFIRM — count-independent "lose" reward; bet-stake gate makes every farm net-negative | sub-real-gas at ≥2 gwei; bet-stake gate the binding floor (§7) |
| `BOUNTY_ETH_TARGET` | `AfKing.sol:261` (deploy-param) | faucet ceiling 8,778,708,333,333 wei (advance-6x @ref); buy-incentive floor ~170e12 (§5 tension) | `885_000_000` (fixture) | **SURFACED — no autonomous change** | SURFACE — recommend faucet ceiling `≤ 8.78e12` wei + flag the buy-incentive-vs-faucet tension (§5); current ~14,000x below | n/a (economic choice; ceiling + tension in §5) |

**Disposition (CORRECTED): the four reward-shape constants (`ADVANCE_RATIO_NUM` / `BUY_RATIO` /
`OPEN_KNEE`) + `RESOLVE_FLAT_BURNIE` keep their literal values; `DOWORK_BATCH` is SPLIT into
`BUY_BATCH = 50` + `OPEN_BATCH = 100`** so the buy leg cannot exceed the 16.7M HARD ceiling. The
331-05 frozen-contract diff is therefore a REAL (still gated) edit — the batch split is behavioral —
plus the `GAS-331 PLACEHOLDER` comment strikes. `BOUNTY_ETH_TARGET` is surfaced as a deploy-param
economic choice with the buy-incentive-vs-faucet tension flagged.

### The exact 331-05 diff (for the USER-APPROVED gate — NOT applied here; line offsets approximate)

```diff
--- a/contracts/AfKing.sol
+++ b/contracts/AfKing.sol
@@ -845,11 +845,14 @@
-    /// @dev GAS-331 PLACEHOLDER — fixed per-leg default batch (the prior caller-bounded
-    ///      default). Calibrated under the USER-gated GAS phase (331), NOT locked here.
-    uint256 internal constant DOWORK_BATCH = 100;
+    /// @dev Buy-leg default batch. Calibrated GAS-331 (correction pass): a LANDED keeper buy is
+    ///      ~262k gas, so 50 buys ≈ 13.1M stays under the 16.7M HARD per-tx ceiling (100 would
+    ///      be ~26M, over the ceiling). Buys must NEVER exceed 16.7M.
+    uint256 internal constant BUY_BATCH = 50;
+    /// @dev Open-leg default batch. Calibrated GAS-331: a typical box open is ~89k gas, so 100
+    ///      opens ≈ 9M (the ~9M average target). The rare all-whale-pass corner (100×~5.4M)
+    ///      exceeds 16.7M and is USER-accepted (statistically unreachable by boon rarity).
+    uint256 internal constant OPEN_BATCH = 100;
     /// @dev GAS-331 PLACEHOLDER — advance reward ratio (2x * mult). Calibrated at GAS (331).
+    /// @dev Advance reward ratio (2x * mult). Calibrated GAS-331 to the advance base marginal;
+    ///      the 1/2/4/6 stall ladder is the escalation lever, faucet-bounded (advance-only).
     uint256 internal constant ADVANCE_RATIO_NUM = 2;
-    /// @dev GAS-331 PLACEHOLDER — buy reward ratio (flat 1.5x per tx = NUM/DEN). At GAS (331).
+    /// @dev Buy reward ratio (flat 1.5x per tx = NUM/DEN). Frozen 329-SPEC D-07 ratio; GAS-331
+    ///      confirms it stays round-trip ≤ 0 at the fixture B (buy is the most expensive leg).
     uint256 internal constant BUY_RATIO_NUM = 3;
     uint256 internal constant BUY_RATIO_DEN = 2;
-    /// @dev GAS-331 PLACEHOLDER — open reward pro-rate knee (1x at/above, pro-rated below).
+    /// @dev Open reward pro-rate knee (1x at/above, pro-rated below). Calibrated GAS-331 —
+    ///      a 1-box mid-day open earns 0.2x, below a one-box tx's gas (small-batch −EV).
     uint256 internal constant OPEN_KNEE = 5;

@@ -876 (doWork buy leg) @@
-            uint256 bought = _autoBuy(DOWORK_BATCH);
+            uint256 bought = _autoBuy(BUY_BATCH);
@@ -888 (doWork open leg) @@
-            uint256 opened = IGame(ContractAddresses.GAME).autoOpen(DOWORK_BATCH);
+            uint256 opened = IGame(ContractAddresses.GAME).autoOpen(OPEN_BATCH);
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

**Additional 331-05 docstring fix (correction #6 — STALE `batchPurchase` rngLock claim):** the
`batchPurchase` docstring at `DegenerusGame.sol:1739` reads "rngLocked / game-over are pre-checked
ONCE at entry for a clean whole-batch abort." That is STALE: the live `batchPurchase` (`:1757-1791`)
has only `msg.sender != AF_KING` (`:1762`) and `gameOver` (`:1763`) entry guards — there is NO
rngLock entry-check (RD-2: keeper BUYS are freeze-safe by construction; a lootbox queues at the
current index pre-entropy, and the orphan hazard is defended on the OPEN side via the autoOpen
word-gate). The docstring should be corrected to drop the "rngLocked … pre-checked" claim. This is a
COMMENT-ONLY contracts edit that folds into the gated 331-05.

```diff
--- a/contracts/DegenerusGame.sol
+++ b/contracts/DegenerusGame.sol
@@ ~1739 (batchPurchase docstring) @@
-    ///      rngLocked / game-over are pre-checked ONCE at entry for a clean whole-batch abort.
+    ///      game-over is pre-checked ONCE at entry for a clean whole-batch abort. There is NO
+    ///      rngLock entry-check: keeper buys are freeze-safe by construction (RD-2) — a lootbox
+    ///      queues at the current index pre-entropy; the orphan hazard is defended on the OPEN
+    ///      side via the autoOpen word-gate, not by blocking the buy.
```

**No `DeployProtocol.sol` change is proposed** (`BOUNTY_ETH_TARGET` is surfaced for the USER as a
deploy-param economic choice, not autonomously tuned — §5). The 331-05 diff now carries a REAL
behavioral change (the `DOWORK_BATCH` → `BUY_BATCH`/`OPEN_BATCH` split) plus the comment strikes — it
is NO LONGER a comment-only / NO-OP. The reward-shape ratio values + `RESOLVE_FLAT_BURNIE` are
unchanged.

> **331-05 gate note (CORRECTED):** the 331-05 diff is NO LONGER comment-only — the
> `DOWORK_BATCH` → `BUY_BATCH=50`/`OPEN_BATCH=100` split is a BEHAVIORAL change (buy batches shrink
> 100→50). Test mirrors that reference `DOWORK_BATCH` MUST be synced when 331-05 lands: grep for
> `DOWORK_BATCH` in `test/` and re-point to the split constants (e.g. `CrankLeversAndPacking.t.sol`,
> any harness asserting the batch literal). The reward-shape ratio values + `RESOLVE_FLAT_BURNIE` are
> unchanged, so their mirrors stay green. The `batchPurchase` rngLock-docstring fix (correction #6) is
> comment-only.

---

## 9. Summary for the 331-05 gate

| Item | Decision (CORRECTED) |
|------|----------|
| `DOWORK_BATCH` (`AfKing.sol:847`) | **SPLIT → `BUY_BATCH = 50` / `OPEN_BATCH = 100`** — buy at the corrected ~262k/item would be ~26M at 100 (> the 16.7M HARD ceiling); 50 ≈ 13.1M. Open at ~89k/item ≈ 9M at 100 (the avg target). Behavioral change behind the 331-05 gate |
| `ADVANCE_RATIO_NUM` (`AfKing.sol:849`) | **CONFIRM `2`** — base ratio; 1/2/4/6 ladder is the escalation lever (one-shot, advance-only) |
| `BUY_RATIO_NUM` / `BUY_RATIO_DEN` (`AfKing.sol:851-852`) | **CONFIRM `3` / `2` (frozen ratio)** — flat 1.5x; buy is now the MOST expensive leg (the most UNDER-reimbursed, §2.1) — value is out of scope, FLAGGED; far-from-binding ceiling 85.2e12 wei |
| `OPEN_KNEE` (`AfKing.sol:854`) | **CONFIRM `5`** — 1-box open = 0.2x, small-batch −EV |
| `RESOLVE_FLAT_BURNIE` (`DegenerusGame.sol:1543`) | **CONFIRM `1e18`** — bet-stake gate dominates; sub-real-gas at ≥2 gwei (unchanged by the buy correction) |
| `BOUNTY_ETH_TARGET` deploy-param | **SURFACED — no autonomous change**; recommended FAUCET ceiling `≤ 8,778,708,333,333 wei` (advance-6x @0.5gwei ref) + FLAG the buy-incentive (~170e12) vs faucet (~8.78e12) tension (§5); current fixture `885,000,000` ~14,000x below (under-incentivizes, not a faucet) |
| Reward-ratio re-analysis (correction) | **buy is the most expensive leg, inverting the original "buy cheapest" rationale; ratios STILL faucet-safe at the fixture B; advance-6x STILL the binding ceiling; buy under-reimbursement FLAGGED** (§2/§2.1/§3) |
| `batchPurchase` rngLock docstring (`DegenerusGame.sol:1739`) | **STALE — fix at 331-05 (comment-only):** claims an rngLock entry pre-check; the live `batchPurchase` has NONE (RD-2, freeze-safe buys). Test `testBatchPurchaseRngLockedRejectsWholeBatchAtEntry` (`CrankNonBrick.t.sol:360`) asserts the unwanted rngLock-abort and FAILS against the live contract — FLAGGED for correction (not fixed here; it asserts behavior the contract correctly does NOT have) |
| CR-01 (per-item MARGINAL, never a single-item total) | **HELD** — every value derived from the N≥32 converged marginal; round-trip ≤ 0 on every leg at the 0.5 gwei reference |
| Level-invariance (GAS-04) | **PROVEN arithmetically** (mp cancels; ETH-equiv = ratio × `BOUNTY_ETH_TARGET` at every level); empirical assert at TST 332 |
| Stall-ceiling (GAS-04) | **1/2/4/6 ADVANCE-ONLY confirmed; NO EXTENSION** — 6x is a one-shot, real-gas safe; any future tier faucet-pool-capped and never lowers existing thresholds |
| Exploitability lens | **REAL prevailing gas (5–50+ gwei) + flip-credit illiquidity**, NOT the 0.5 gwei reference (`feedback_bounty_exploit_uses_real_gas_not_peg_ref`) |
| Contract approval | **REQUIRED at 331-05 — nothing pre-approved.** This correction pass touches NO `contracts/*.sol`; the 331-05 diff is now a REAL (gated) batch-split + comment strikes |

---

## 10. Task-2 attestation — level-invariance + stall-ceiling (GAS-04)

The GAS-04 deliverables are recorded in this document:

- **Level-invariance (§6):** PROVEN arithmetically — `mp` cancels in `ratio * unit * mp /
  PRICE_COIN_UNIT = ratio * BOUNTY_ETH_TARGET`, so the ETH-equivalent reward is invariant across the
  full `priceForLevel` ladder (worked at 3 levels: 0.01 / 0.08 / 0.24 ETH, all recover `B`). The
  empirical on-chain assertion (the `SweepPerPlayerWorstCaseGas.t.sol:188-211` shape-insensitivity
  idiom) is deferred to TST Phase 332 (TST-04); this record proves the arithmetic.
- **Stall ceiling (§4):** the 1/2/4/6 ladder is CONFIRMED ADVANCE-ONLY (the autoBuy stall ladder was
  deleted per D-07 — advance is the sole stall epoch, invariant (d) satisfied-by-deletion); existing
  thresholds (20 min / 1 h / 2 h) are NEVER lowered. The GAS-data-derived decision is **NO
  EXTENSION above the 2-hour tier**: the 6x peak is a ONE-SHOT (one rewardable advance per day-move,
  un-fakeable on demand, real-gas safe at ≥1 gwei), so a higher tier adds no liveness benefit and
  would only widen the reference-price over-reimbursement. Any future extension must be capped against
  the finite flip-credit faucet pool and may only ADD tiers above 2h.
- **Exploitability lens:** judged against REAL prevailing gas (5–50+ gwei) + flip-credit illiquidity,
  NOT the 0.5 gwei reference (`feedback_bounty_exploit_uses_real_gas_not_peg_ref`).

---

## 11. CORRECTION-PASS disposition summary (2026-05-27)

The six corrections from the correction-pass directive, as resolved in this record + the harness
(commit `322fd972`):

1. **BUY harness fixed.** The buy non-vacuity oracle is now `lootboxEthBase[index][player] > 0` (the
   buy LANDED), not the `lastAutoBoughtDay` stamp (which survives a try/catch-reverted slice). The
   keeper buy is forced-lootbox (ticketQuantity=0) so a slice < `LOOTBOX_MIN (0.01 ether)` reverted
   inside `batchPurchase`'s per-player try/catch while the day-stamp falsely passed → the old `40,224`
   was the revert-catch path. **Corrected LANDING buy marginal ~261,809** (clean N32 ~255,614); buys
   verified to land with DirectEth funding (msgValue == slice == mp == 0.01 ETH == LOOTBOX_MIN).

2. **OPEN whale-pass branch found + measured.** The whale-pass BOON (type 28) reachable from a box
   open runs `_activateWhalePass` (100-iter ticket-queue loop) — **~5,396,350 gas/box**, ~60x the
   typical ~89k. The >5 ETH `LOOTBOX_CLAIM_THRESHOLD` "defer to claim" branch is the JACKPOT/DECIMATOR
   payout path (cheap, NOT the per-box open path). The whale-pass box is the true open worst case
   (rare). Typical box marginal unchanged (~89,288).

3. **30M → 16.7M.** All ceiling references corrected to the 16.7M effective gas-target; the DEFAULT
   box buy/open leg targets a ~9M average.

4. **Split caps sized.** `BUY_BATCH = 50` (HARD: 50×262k ≈ 13.1M < 16.7M; buys NEVER exceed 16.7M) /
   `OPEN_BATCH = 100` (typical 100×89k ≈ 9M avg). The all-whale-pass open corner (100×~5.4M) exceeds
   16.7M and is USER-ACCEPTED (statistically unreachable by whale-pass-boon rarity).

5. **Reward-ratio re-analysis.** Buy (~262k) is now the MOST expensive per-item leg, inverting the
   "buy cheapest → richest 1.5x" rationale. (a) The frozen ratios (1.5/1.0/2.0, knee=5) STILL avoid a
   faucet at the current `BOUNTY_ETH_TARGET` — every leg round-trip ≤ 0 at 0.5 gwei + at all market
   prices (§3). (b) Advance-6x is STILL the binding faucet ceiling (8.78e12 wei); the buy faucet
   ceiling ROSE to ~85e12 (less binding, as predicted). The buy UNDER-reimbursement keeper-incentive
   implication is FLAGGED (§2.1, §5) — the buy leg is the binding INCENTIVE consideration if the USER
   tunes B upward, pulling against the faucet ceiling. Ratio values unchanged (frozen, out of scope).

6. **rngLock disposition (USER-resolved).** BUYING lootboxes during rngLock is FINE (commit-before-
   reveal; `batchPurchase` intentionally has NO rngLock guard — only `AF_KING` + `gameOver` at
   `:1762-1763`). OPENING is blocked (autoOpen `:1671` no-ops, openLootBox `:2162` reverts, the
   `:1683` word-gate). Two stale artifacts FLAGGED for 331-05:
   - the `batchPurchase` docstring `:1739` falsely claims an rngLock entry pre-check (comment-only fix,
     §8 diff);
   - `testBatchPurchaseRngLockedRejectsWholeBatchAtEntry` (`CrankNonBrick.t.sol:360`) asserts the
     unwanted rngLock whole-batch abort and FAILS against the live contract (it expects `RngLocked()`;
     the live `batchPurchase` correctly does not revert). This is one of the known baseline failures —
     it asserts behavior the contract correctly does NOT have. NOT fixed in this pass (test correction
     belongs with the 331-05 docstring fix or a dedicated test pass).
