# 392-03 — NET 2 (Claude adversarial net) — ENTROPY-AND-ECON / reward game-theory (ECON slice)

**Subject (byte-frozen):** `a8b702a7` (contracts tree pin `2934d3d8987a09c5f073549a0cb499f6c5f28620`;
`git diff a8b702a7 -- contracts/` EMPTY before and after this task).
**Baseline oracle:** `test/REGRESSION-BASELINE-v63.md` — forge **854 / 0 / 110** (the expected forge-failure
name-set is strictly EMPTY at this subject).
**Net:** NET 2 = the deep Claude adversarial net. Run INDEPENDENTLY of the council (the EV/accrual/
money-pump/scarce-supply claims were attacked against the FROZEN source FIRST; the NET-1 council leads
[`392-01-COUNCIL-NET.md` + `council/econ.gemini.txt`] are folded in at §7, AFTER the independent pass).
**Source-read convention:** every cite read via `git show a8b702a7:contracts/<File>.sol` (working tree
ignored). Line numbers are at the frozen subject. **Posture: AUDIT-ONLY** — a CONFIRMED finding is
DOCUMENTED + ROUTED, never fixed here.
**Threat weighting (AUDIT-V63-PLAN §4, USER-locked):** a closed positive-EV money pump = **HIGH**; a
scarce-asset supply break (an extra whale half-pass beyond the per-bracket cap) = value-bearing; an
unbounded accrual grind = value-bearing. RNG/freeze = DOMINANT (391's); solvency = SPINE (390's). A
documented-change DESIRABILITY complaint is NOT a finding (§5 design-intent anchor: VERIFY the documented
EV-neutrality / two-EV-changes claims hold in code; do NOT re-litigate intent).

---

## §0 — Method & frozen-source pins used by every item

Path map at `a8b702a7`: storage is `contracts/storage/DegenerusGameStorage.sol` (NOT the root path the
plan's interface comment assumed). The ECON-load-bearing constants/functions, all re-read at the subject:

| Constant / function | Value / role | Frozen cite |
|---|---|---|
| `LOOTBOX_EV_MIN_BPS` | 9_000 (90% floor at score 0) | Storage:1543 |
| `LOOTBOX_EV_NEUTRAL_BPS` | 10_000 (100% at score 6_000) | Storage:1545 |
| `LOOTBOX_EV_MAX_BPS` | 14_500 (145% ceiling) | Storage:1547 |
| `LOOTBOX_EV_ACTIVITY_NEUTRAL_BPS` | 6_000 (neutral score) | Storage:1539 |
| `LOOTBOX_EV_ACTIVITY_MAX_BPS` | 40_000 (score-to-ceiling) | Storage:1541 |
| `LOOTBOX_EV_BENEFIT_CAP` | 10 ether (per (player,level)) | Storage:1549 |
| `ACTIVITY_SCORE_HARD_CAP_BPS` | 65_534 (total score clamp) | Storage:143 |
| `_lootboxEvMultiplierFromScore` | linear 9000→10000 (0..6000), 10000→14500 (6000..40000), 14500 above | Storage:1619-1640 |
| `_applyEvMultiplierWithCap` | bonus-only cap draw; penalty/neutral apply on full amount, draw nothing | Lootbox:474-512 |
| `_resolveLootboxRoll` | roll%20 split: <8 / <11 / <14 / <17 / <19 / else | Lootbox:1965-2049 |
| `LOOTBOX_TICKET_ROLL_BPS` | 19_678 (= 16100 × 11/9) | Lootbox:243 |
| `LOOTBOX_TICKET_FAR/NEAR_BUDGET_BPS` | 15_000 / 8_750 (1.5× / 0.875×) | Lootbox:248-249 |
| variance tier chances | 100/400/2000/4500 (rest 3000) bps = 1/4/20/45/30% | Lootbox:251-257 |
| variance tier ranges | T1 32000-60000, T2 16000-30000, T3 8000-14000, T4 4510-8510, T5 3000-6000 | Lootbox:263-272 |
| recycle kicker gate | `if (totalClaimableUsed >= priceWei * 3)` (drain-detection DELETED) | Mint:1740 |
| recycle kicker payout | `(totalClaimableUsed * PRICE_COIN_UNIT * 10)/(priceWei * 100)` via `coinflip.creditFlip` | Mint:1741-1745 |
| presale box-credit | `presaleBoxCredit[buyer] += (ticketCost + lootBoxAmount)/4` if `!presaleOver` | Mint:1725-1727 |
| `creditFlip` | routes to `_addDailyFlip(player, amount, 0, false, false)` — illiquid, must survive a 50/50 flip | Coinflip:903-908 |
| quest streak score | `bonusBps += uint256(questStreak) * 50` (uncapped), total clamped to 65_534 | MintStreakUtils:314, 349-351 |
| `_score` | S = A + 2·H, all 4 colors + 4 symbols (hero ×2) ⇒ S=9 needs all 8 axes match | Degenerette:1001-1029 |
| `_degTrait` | symbol uniform 1/8; color base-15 (gold 1/15, 7 commons 2/15 each) | DegenerusTraitUtils:201-224 |
| `wwxrpJackpotWhalePassBracketAwarded[bracket]` | GLOBAL per-bracket flag shared box-route (Degenerette:1325) ∧ bet-route (Degenerette:751) | Degenerette |
| `payAffiliate` access | GAME-only (`msg.sender != GAME revert`) | Affiliate:418 |
| self-referral guard | `resolved == sender ⇒ VAULT 0% kickback (noReferrer)` | Affiliate:439-444 |
| `affiliateBonusPointsBest` | monotonic sum, early-break at 25 ether (clamped) | Affiliate:720-730 |

For each item below: PROPERTY · attack/cycle/cost tried · binding bound / EV-arithmetic / saturation /
supply-flag / decay-gate · provisional verdict (CONFIRMED / REFUTED / BY-DESIGN / MONITOR).

---

## §1 — ECON-01: bounded-accrual sweep (dedicated, per reward surface)

**Property:** every reward consumer saturates BELOW its hard ceiling; the now-uncapped quest-streak input
widens no downstream reward ceiling; no unbounded grind exists.

**Attack:** push the uncapped `questStreak` (uint16, rate-bounded ≤3/day — see §6) arbitrarily high and
trace whether ANY downstream reward exceeds its prior saturation ceiling.

**Trace (each surface, binding bound re-read at source):**

| Reward surface | Uncapped input? | Binding bound that saturates (cite) | Saturates below cap? |
|---|---|---|---|
| Activity score total | `questStreak*50` uncapped (MintStreakUtils:314) | `ACTIVITY_SCORE_HARD_CAP_BPS = 65_534` clamp at MintStreakUtils:349-351 | YES (hard clamp) |
| Lootbox EV multiplier | score | saturates at `LOOTBOX_EV_ACTIVITY_MAX_BPS = 40_000` ⇒ 14_500 bps (145%) max, Storage:1629-1630; + 10-ETH/(player,level) benefit cap, Lootbox:489-512 | YES (40_000 < 65_534) |
| Degenerette ROI / WWXRP high-ROI | score | `_roiBpsFromScore` / `_wwxrpHighValueRoi` saturate at `ACTIVITY_SCORE_MAX_BPS = 30_500` (Degenerette ROI tables) | YES (30_500 < 65_534) |
| Terminal-decimator boost | streak | streak re-clamped to 100 inside `_terminalDecBoostFactorBps` (factor ≤20×) | YES (independent of the score path) |
| BURNIE survival flip | per-bet | EV-neutral ×2 at 50/50, freeze-safe seed (391 §RNG-03) | bounded per-bet |
| Lootbox spins (WWXRP/BURNIE/ETH) | box amount | inherit the capped `scaledAmount` (Lootbox:474); recursion depth 1 (ETH-spin recirc opens with `allowEthSpin=false`, Degenerette:1463) | bounded |
| Recycle bonus | recycled claimable | 10% illiquid BURNIE flip-credit (Mint:1741), no closed loop (§4) | bounded |
| Whale half-pass via box WWXRP-spin | box opens | one per 10-level bracket, global flag (Degenerette:1325) | supply-capped (§5) |
| BURNIE seed emission | — | flip-survival before mint; supply invariant intact (392-04 owns) | bounded |

**Settling bound:** the streak only changes TIME-TO-CEILING (the marginal score gain rose from +100 bps/day
to +150 bps/day, ~3× faster ramp; the surface map's ~33-day decimator-max / ~203-day ROI-max / ~267-day
EV-max figures), NOT the ceiling itself. Every consumer's saturation threshold (40_000 EV / 30_500 ROI /
streak-clamp-100 decimator) is BELOW the 65_534 hard cap, so an arbitrarily high streak hits the
consumer's own cap and stops. No surface admits unbounded reward accrual.

**Provisional verdict: REFUTED** (every consumer saturates below its hard bound; the uncapped streak
widens no ceiling — only the ramp speed, which is the documented "halve + uncap" intent).

---

## §2 — ECON-02: EV-neutrality re-verified IN CODE (dedicated arithmetic, matched to the PAPER brief)

**Property:** each documented EV-neutral redistribution's CODED value equals its claimed EV-neutral target
(not hand-waved). Attack: hunt a fat-finger constant, an asymmetric range, a budget that does not net to 1.

### (i) Reward split = 40 / 15 / 15 / 15 / 10 / 5 (roll % 20)
`_resolveLootboxRoll` (Lootbox:1980-2049): `roll = uint16(seed>>40) % 20`; branches `<8` (8/20 = **40%**
tickets), `<11` (3/20 = **15%** DGNRS), `<14` (3/20 = **15%** WWXRP-spin), `<17` (3/20 = **15%** BURNIE
flat), `<19` (2/20 = **10%** BURNIE-spins ×3), `else` (1/20 = **5%** ETH-spin). **MATCHES** the brief §2.

### (ii) Ticket-roll budget ×11/9 = 19,678 bps, aggregate ticket value preserved
`LOOTBOX_TICKET_ROLL_BPS = 19_678` (Lootbox:243). Check: 16_100 × 11/9 = 19_677.7 → **19_678** (rounded).
Aggregate preservation across the 55%→45% frequency drop: old 0.55 × 16_100 = **8_855.0**; new 0.45 ×
19_678 = **8_855.1**. **PRESERVED** (≤0.002% rounding).

### (iii) Far/near budget weighting → 1.000 exactly EV-neutral
`LOOTBOX_TICKET_FAR_BUDGET_BPS = 15_000` (1.5×), `LOOTBOX_TICKET_NEAR_BUDGET_BPS = 8_750` (0.875×)
(Lootbox:248-249); far share 20% / near 80% (the brief §4/§5). Check: 0.2 × 1.5 + 0.8 × 0.875 = 0.30 +
0.70 = **1.000**. **EXACTLY EV-NEUTRAL.** `_ticketBudget` (Lootbox:2055-2068) applies it as
`(amount × 19678 / 10000) × (far?15000:8750) / 10000`.

### (iv) Variance tiers — symmetric ranges centered on the old static value, EV 0.786× preserved
Chances `LOOTBOX_TICKET_VARIANCE_TIER{1..4}_CHANCE_BPS` = 100/400/2000/4500, rest 3000 (Lootbox:251-257) =
**1/4/20/45/30%** (unchanged). Ranges (Lootbox:263-272), midpoint = old static value:

| Tier | Chance | Range (BPS → ×) | Midpoint × | Old static × | Contribution (chance × mid) |
|---|---|---|---|---|---|
| 1 | 1% | 32000-60000 → 3.20-6.00 | 4.60 | 4.6 | 0.0460 |
| 2 | 4% | 16000-30000 → 1.60-3.00 | 2.30 | 2.3 | 0.0920 |
| 3 | 20% | 8000-14000 → 0.80-1.40 | 1.10 | 1.1 | 0.2200 |
| 4 | 45% | 4510-8510 → 0.451-0.851 | 0.651 | 0.651 | 0.29295 |
| 5 | 30% | 3000-6000 → 0.30-0.60 | 0.45 | 0.45 | 0.1350 |

Sum = 0.0460 + 0.0920 + 0.2200 + 0.29295 + 0.1350 = **0.78595 ≈ 0.786×** = the documented overall variance
EV. Each range is SYMMETRIC about the old static value (mid = (low+high)/2). `_ticketRangeBps`
(Lootbox:2221-2233) linearly maps a uniform within-tier roll to the inclusive [low,high] so the mean is the
midpoint. Drawn from the SAME `varianceRoll` that selects the tier (`uint24(seed>>96) % 10_000`,
Lootbox:2179) — no extra entropy. **PRESERVED, no asymmetric range, no fat-finger constant.**

**Settling arithmetic:** every coded value matches its claimed EV-neutral target — split (40/15/15/15/10/5),
×11/9 (19,678 → 8,855 == 8,855), far/near (1.000 exactly), variance (0.78595 == 0.786). **REFUTED** (no
divergence; the redistributions are EV-neutral in code as documented).

---

## §3 — ECON-03: the two genuine EV changes match documented intent IN CODE

**Property:** the EV-multiplier band IS 9000-14500 with score-to-ceiling 40,000; the recycle gate IS
≥3-whole-ticket with drain-detection removed.

### (i) EV-multiplier band
Storage:1543/1545/1547 = `LOOTBOX_EV_MIN_BPS = 9_000` (90% floor), `LOOTBOX_EV_NEUTRAL_BPS = 10_000`
(100% at score `LOOTBOX_EV_ACTIVITY_NEUTRAL_BPS = 6_000`), `LOOTBOX_EV_MAX_BPS = 14_500` (145% ceiling) at
`LOOTBOX_EV_ACTIVITY_MAX_BPS = 40_000`. `_lootboxEvMultiplierFromScore` (Storage:1619-1640): linear
9000→10000 over score 0..6000, linear 10000→14500 over score 6000..40000, clamp 14500 above. **MATCHES**
the brief §1 (floor 80%→90%, ceiling 135%→145%, score-to-ceiling 25,500→40,000). The wider score-to-ceiling
is the documented consequence of the uncapped quest-streak.

### (ii) Recycle gate
Mint:1740 `if (totalClaimableUsed >= priceWei * 3)` — ≥3 whole tickets' worth of recycled claimable, with
NO `spentAllClaimable` drain-detection check (the old all-claimable gate is DELETED; only the ×3 threshold
remains). Bonus magnitude unchanged: 10% of recycled value (Mint:1741-1744). **MATCHES** the brief §7.

**Settling cite:** both EV changes match the documented numbers in code. **REFUTED-as-divergence** (the
two changes are exactly the documented intent).

### (iii) FC-392-04 — stale EV-band comment (comment-only)
Lootbox:472-473 still documents "EV multiplier in basis points (8000-13500)" in the `_applyEvMultiplierWithCap`
NatSpec, after the band moved to 9000-14500 (the live constants at Storage:1543-1547 are correct). The
`_lootboxEvMultiplierFromScore` NatSpec (Storage:1618) correctly says "(9000-14500)". Comment-only staleness,
no logic impact. **MONITOR/INFO** — not a logic finding.

---

## §4 — ECON-04: money-pump composition search (DEDICATED — the PRIORITY adjudication)

**Property:** no closed repeatable cycle nets value-out > value-in across the recycle / spin / recirc /
carry / affiliate compositions.

**The gemini HIGH claim (NET 1):** a player at activity score ≥6,000 (EV multiplier = 100% neutral)
recycles 1 ETH of claimable into boxes, expects 1 ETH back, AND collects 0.1 ETH BURNIE flip-credit as
"pure profit" = a repeatable ≥110% RTP loop. gemini asserts the 10-ETH benefit cap only bounds the uplift
ABOVE 100%, leaving floor + bonus uncapped.

**Per-leg wei/value accounting against the frozen source (the accounting gemini did not show):**

Consider ONE loop iteration: a player recycles `V` wei of WON claimable into a buy that recycles ≥3 whole
tickets' worth (so the kicker fires). Track every value flow:

| Leg | Value-out to the player | Source / cite | Realized (liquid ETH-equivalent) |
|---|---|---|---|
| **A. Box stake at 100% EV** | the box pays its OWN reward-component EV, NOT a guaranteed 100% ETH return | `_applyEvMultiplierWithCap` at neutral returns `amount` unscaled (Lootbox:483-485); the box `amount` is then SPLIT into the §2 rolls (40% tickets, 15% DGNRS, 15% WWXRP-spin, 15% BURNIE-flat, 10% BURNIE-spins, 5% ETH-spin) | < V in **liquid ETH** — only the 5% ETH-spin slice and the (illiquid, future-level, variance-discounted) tickets are ETH-denominated; 40% of the box value is non-ETH (BURNIE/WWXRP/DGNRS-from-a-finite-pool) |
| **B. Recycle kicker** | 10% of `V` as BURNIE **flip-credit** | Mint:1741 `coinflip.creditFlip(buyer, ...)` → `_addDailyFlip(player, amount, 0, false, false)` (Coinflip:903-908) | ≤ 0.10·V × **0.5** (must SURVIVE a 50/50 flip to mint) × the BURNIE peg-vs-realizable discount (≈0.59:1 per the brief §ref) ⇒ realized ≈ 0.10·V × 0.5 × (illiquid BURNIE) ≪ 0.10·V |

**Why the EV multiplier is NOT a "100% guaranteed return":** the EV multiplier scales the box `amount`; at
score 6,000 it scales by 1.000, i.e. it does NOT add value. The box then resolves its rolls, and the box's
own component EV is the by-design Degenerette/lootbox RTP — the value-out of the box is the reward
components, NOT the staked ETH back. The "100% neutral" multiplier means the box neither inflates nor
deflates the box's intrinsic budget; it does NOT guarantee 100% liquid-ETH return on the recycled stake.
The DIRECT-open box EV in liquid ETH is sub-unity (the value is reshaped into illiquid tickets / BURNIE /
WWXRP / a finite DGNRS pool). gemini's "expect 1 ETH back" conflates the EV-multiplier=1.0 with a
guaranteed-1.0-ETH return — these are different.

**Why the kicker is not "pure profit":** the 10% kicker is BURNIE flip-credit (Mint:1741 → `_addDailyFlip`,
Coinflip:903). It is NOT minted ETH — it must (a) survive a 50/50 survival flip before it mints (expected
0.5×), and (b) BURNIE is valued at the protocol peg but realizable below it (illiquid flip-credit, the
brief §ref ≈0.59:1). So the realized value of a 0.10·V nominal kicker is ≈ 0.10·V × 0.5 × 0.59 ≈ **0.030·V**
in liquid ETH-equivalent, far below the 0.10·V gemini treats as cash.

**Why the loop is not closed:** the value-in `V` is REAL WON claimable ETH (a positive-variance event must
occur first to mint claimable). The value-out is (sub-unity box reward components in illiquid/finite-pool
form) + (a ≈0.030·V realized illiquid kicker). For the loop to be a money pump, value-out must exceed `V` in
the SAME liquid denomination on a REPEATABLE basis. It does not: each iteration converts liquid won
claimable into a basket dominated by illiquid/discounted assets plus a flip-gated kicker — the realized
liquid output is **< V**. The cycle is value-LOSING per iteration in liquid terms.

**The composition legs (stacking attack):**
- **Kicker + presale 25% box-credit:** Mint:1725-1727 `presaleBoxCredit[buyer] += (ticketCost +
  lootBoxAmount)/4` — this is **spendable box CREDIT** (restricted to buying more boxes), gated `!presaleOver`
  (a one-time presale window, not perpetual), and it credits the SPEND (not pure profit) — it is a discount
  on FUTURE box purchases, not a withdrawable asset. It cannot close a liquid-ETH-out loop: it only buys
  more sub-unity boxes during a finite presale.
- **Spin recirc:** ETH-spin → 1 recirc box with `allowEthSpin=false` (Degenerette:1463) ⇒ recursion depth
  1, no cascade. The recirc box pays its own sub-unity rolls. Adds no closed positive loop.
- **Auto-rebuy carry / affiliate flip-credit:** both route through `creditFlip` (illiquid BURNIE) and the
  affiliate 75/20/5 is intra-upline-redistributive (buyer never wins, §FC-392-14). Neither adds liquid
  value-out to the recycler's own cycle.

**The 10-ETH benefit cap point (gemini's "cap only bounds the uplift"):** TRUE but irrelevant to the pump.
`_applyEvMultiplierWithCap` (Lootbox:483-485) returns `amount` unscaled at neutral (≤ NEUTRAL draws nothing
from the cap), and the bonus-only cap binds the uplift ABOVE 100% — but the floor (90%) is a PENALTY
(value-losing) and "neutral" (100%) is no value added. There is no "uncapped floor + bonus = pure profit"
because the floor adds nothing positive and the bonus (kicker) is illiquid/flip-gated/sub-0.10·V realized.
The cap not covering the floor is harmless: the floor is ≤ 100%, never a profit source.

**Settling reason:** every composition's value-out is illiquid / sub-100%-direct-EV / capped / finite-pool
vs the real WON claimable value-in. No closed repeatable cycle nets liquid value-out > value-in. **REFUTED**
(no money pump). FC-392-06 (recycle kicker on partial spends) and FC-392-09 (ETH-spin "EV-equal to the
tickets it replaces" routed through the >100%-RTP Degenerette) fold in: FC-392-06 is the same illiquid
flip-credit gate (bounded, no loop); FC-392-09's aggregate box EV uplift is bounded by the 10-ETH per-
(player,level) benefit cap (Lootbox:489-512) — the recirc box's EV adjustment funnels into the SAME packed
cap (§5).

**Skeptic dual-gate (run because a money pump = HIGH if confirmed):**
- **Structural-protection check:** the kicker is illiquid BURNIE flip-credit (must survive a flip + peg
  discount); the box direct EV is sub-unity in liquid ETH; the value-in is won claimable (positive-variance
  seeded, not free); the presale credit is box-spend-restricted + presale-windowed; the EV uplift is 10-ETH
  capped per (player,level). FOUR independent structural protections.
- **3-condition EV lens:** (1) reachable? yes (recycle is a normal flow). (2) profitable? **NO** — realized
  liquid value-out (< V) < value-in (V); the kicker realizes ≈0.030·V, not 0.10·V; the box reshapes V into
  illiquid/sub-unity assets. (3) repeatable/grindable for net gain? **NO** — each iteration is liquid-value-
  losing, so iterating compounds the loss, not a profit.
- **Gate result:** NOT a money pump — fails the profitability condition. The claim is a STRUCTURAL assertion
  ("cap doesn't cover the floor") that does not survive the per-leg liquid accounting. **REFUTED** (no HIGH).

---

## §5 — ECON-05 / FC-392-07: whale-half-pass channel (DEDICATED quantification)

**Property:** the box WWXRP-spin (15% of opens, S==9) stays near-unfarmable AND no path mints a half-pass
beyond the per-bracket cap.

**P(S==9) quantification from the frozen trait/score code:**
- `_score` (Degenerette:1001-1029): S = Σ over 4 quadrants [color-match(+1) + symbol-match(+1, or +2 for
  the hero quadrant)]. S=9 requires ALL 4 color axes match AND ALL 4 symbol axes match (4 colors + 3
  non-hero symbols + 1 hero symbol×2 = 4+3+2 = 9). So S=9 ⇔ all 8 axes match between playerTicket and
  resultTicket.
- `_degTrait` (DegenerusTraitUtils:201-224): symbol = uniform 1/8 (3 bits). Color = base-15: gold (color 7)
  P=1/15; each of the 7 common colors P=2/15.
- P(one color axis matches, two independent draws) = Σ_c P(c)² = 7·(2/15)² + (1/15)² = 28/225 + 1/225 =
  29/225 ≈ **0.12889**.
- P(one symbol axis matches) = Σ_s (1/8)² = 8·(1/64) = **1/8 = 0.125**.
- P(S=9) = (29/225)⁴ × (1/8)⁴ = (0.12889)⁴ × (0.125)⁴ ≈ 2.760e-4 × 2.441e-4 ≈ **6.74e-8** per WWXRP spin.

**Boxes-per-pass acquisition cost:** the box WWXRP-spin fires on 15% of opens (roll ∈ {11,12,13} of 20).
P(whale-pass attempt resolves S=9 per box open) = 0.15 × 6.74e-8 ≈ **1.01e-8**. Expected box opens per
half-pass ≈ 1 / 1.01e-8 ≈ **~99 million box opens** (each box costs real ETH). This is FAR beyond the
by-design "near-unfarmable" bar — the new channel changes the cost CURVE negligibly (the deliberate-WWXRP-
bet route already had the same per-spin P(S=9); the box route just lets a 15% slice of an open also roll
it). The `betAmount >= MIN_BET_WWXRP` gate (Degenerette:1323) holds: the box stakes `LOOTBOX_WWXRP_PRIZE =
1 ether` == `MIN_BET_WWXRP = 1 ether` (Lootbox:282, Degenerette:248), so the gate passes by exactly meeting
the floor — no sub-min farming.

**Per-bracket supply cap (the value-bearing half):** the flag `wwxrpJackpotWhalePassBracketAwarded[bracket]`
(bracket = `level/10`) is checked-then-set in BOTH the box route (Degenerette:1325-1327) and the regular
WWXRP-bet route (Degenerette:751-753) — the SAME storage slot. Once any route sets it for a bracket, every
later route (box or bet) reads `true` and skips the award. **One half-pass per 10-level bracket regardless
of route — supply is capped, no break.** No race can mint >1: solidity execution is sequential within a tx,
and across txs the flag is a committed SSTORE (a second tx reads the set flag). A recirc box (ETH-spin →
recirc) opens with `allowEthSpin=false` but can still roll WWXRP-spin — yet the same per-bracket flag still
caps it; even two WWXRP-spins in one open (parent + recirc, both S=9, vanishingly unlikely at 6.74e-8 each)
hit the same flag, the second is a no-op.

**Settling cite:** P(S=9) ≈ 6.74e-8, boxes-per-pass ≈ 99M opens (cost intact above near-unfarmable); the
global per-bracket flag (Degenerette:1325, shared with :751) caps supply at one per bracket across all
routes. **BY-DESIGN** — the acquisition channel changed (a cost-curve change), supply intact
([[degenerette-wwxrp-rtp-by-design]]). Not a supply break; not a finding. (Skeptic gate: a supply break
would be value-bearing, but supply is provably capped — the gate finds no value-bearing break.)

---

## §6 — ECON-06 + FC-392-01 / FC-392-02: quest-streak rate-bound + decay-gate (DEDICATED)

**Property:** the now-uncapped/halved streak is rate-bounded (≤3/day) and decay-gated; the ceiling is
reachable only by intended sustained effort.

**The gemini HIGH claim (NET 1):** toggling afking↔manual on the same day harvests BOTH an afking-delivered
streak AND a manual slot-0 +1, breaching the ≤3/day bound.

**Trace of the streak-credit machinery at the frozen source:**
- `_questComplete` (Quests:1707-1768): `completionMask` (per-day, per-slot) dedups — `if ((mask & slotMask)
  != 0) return (0, ..., false)` (Quests:1708-1711). Each slot (0 and 1) credits at most once per day.
  `_questSyncState` resets `completionMask = 0` on a day change (Quests:1457-1460).
- The afking branch: `bool afking = state.afkingActive` (Quests:1716). If `afking`, slot-0 completion is
  **streak-neutral** (the `if (!afking)` block at Quests:1745-1752 is skipped — no `state.streak += 1`);
  only a slot-1 secondary calls `recordAfkingSecondary` (Quests:1753-1754). Off-run (`!afking`), slot-0 and
  slot-1 each `state.streak += 1` once/day, and slot-0 sets `lastCompletedDay` (Quests:1751).
- `_effectiveQuestStreak` (Storage:2284-2293): if NOT afking → returns the manual decay-aware streak; if
  afking-live → returns the afking compute-on-read (`_afkingStreak`) and IGNORES the manual streak. The two
  are **mutually exclusive** — never summed.
- `_afkingStreak` (Storage:2257-2261) = `_streakBaseOf(sub) + (afkCoveredThroughDay - afkingStartDay)`. The
  base = the snapshot at `beginAfking` (Quests:459, captures `state.streak`) + in-run secondaries
  (`recordAfkingSecondary` +1 each, GameAfkingModule:1717-1724). Funded delivered days = the span the auto-
  buy actually paid.

**Attack — same-day toggle (FC-392-02):**
1. While afking, complete slot 0: streak-neutral (no +1), `completionMask` bit 0 SET.
2. `finalizeAfking` (Quests:486-504): sets `state.streak = earnedStreak`, anchors `lastActiveDay`/
   `lastCompletedDay = lastValid`.
3. Off-run, complete slot 0 AGAIN same day: `completionMask` bit 0 is already SET ⇒ `_questComplete` returns
   `(0, ..., false)` — **NO +1**. The double-count is BLOCKED by the per-day per-slot mask.

Even if the player completes slot 0 manually FIRST (off-run, +1, mask bit 0 set), then `beginAfking`: the
snapshot captures `state.streak` (incl. the +1) as the run BASE; the funded delivered-day span for the
SAME start day is `(covered - start)` = 0 for the start day (no extra day added). The manual +1 and the
funded delivery for one day are NOT both counted as separate increments. While afking-live the manual
streak is IGNORED entirely (`_effectiveQuestStreak`). **No double-channel exists** — the afking slot-0 skip
(Quests:1745) is precisely the guard that prevents it.

**Rate bound:** ≤3 increments/day — slot 0 (once, mask-deduped), slot 1 (once, mask-deduped), level-quest
(once per level, FC-392-01). Each gated independently; `completionMask` (slots 0/1) + the `1<<136` level-
quest completion flag (Quests:2052) enforce once-each.

**Decay-gate:** `_effectiveBaseStreak` / `_questSyncState` (Quests:1115-1127, 1428-1461): the decay anchor
is `lastActiveDay` (fallback `lastCompletedDay`), updated ONLY on slot-0 completion (Quests:1727-1729,
1751). If `currentDay > anchorDay + 1` and `missedDays > streakShield` ⇒ `streak = 0`. So a high streak
requires DAILY slot-0 (primary) completion — not free.

**FC-392-01 (level-quest +1 off the primary gate):** `_handleLevelQuestProgress` (Quests:2017-2076) credits
`qs.streak += 1` (off-run) or `recordAfkingSecondary` (afking) on a level-quest completion gated by
`_isLevelQuestEligible` + once-per-level (`1<<136`), WITHOUT updating `lastActiveDay` (Quests:2059-2068).
The +1 is locked into `state.streak` immediately but is at DECAY RISK next day: the decay anchor is still
the last slot-0 day, so if the player then skips the primary, `_questSyncState` zeroes the streak (anchor
stale). So the level-quest +1 is a BOUNDED off-day bump (one per level, level-progression-rate-limited) that
the daily-primary decay gate self-corrects. Not an unbounded or persistent bypass. **REFUTED** (bounded +
decay-corrected).

**Settling cite:** `completionMask` per-day-per-slot dedup (Quests:1708) + the afking slot-0 streak-skip
(Quests:1745) + the mutually-exclusive `_effectiveQuestStreak` (Storage:2284) + the slot-0-only decay anchor
(Quests:1115/1428). The same-day double-channel is BLOCKED; the rate is ≤3/day; the ceiling needs sustained
daily primary effort.

**Skeptic dual-gate (run because a rate-bound breach feeding faster max-EV access could be elevated):**
- **Structural-protection check:** the mask dedups slot 0 once/day; the afking branch makes slot 0 streak-
  neutral specifically to prevent the double-channel; the afking and manual streaks are mutually exclusive
  (never summed); the decay anchor zeroes a streak that misses the daily primary.
- **3-condition EV lens:** (1) reachable double-count? NO — mask + afking-skip block it. (2) even a
  hypothetical transient +1 — profitable? the CEILINGS are FIXED (40,000 EV / 30,500 ROI / streak-clamp-100
  decimator, all < 65,534 hard cap, §1); a faster ramp does NOT raise any ceiling, only time-to-ceiling —
  the documented "halve + uncap" intent. (3) grindable? NO — bounded ≤3/day, decay-gated on the daily
  primary.
- **Gate result:** NOT a rate-bound breach (no double-channel) and, even if a transient over-count existed,
  the fixed ceilings make it a ramp-SPEED matter (documented intent), not a ceiling-breach. **REFUTED** (no
  HIGH). The likely USER disposition for FC-392-01's level-quest +1 (decay-corrected) is doc-only/INFO.

---

## §7 — Remaining owned leads (FC-392-03, -05, -10, -14, -15) + council fold-in

### FC-392-05 (VERIFY-claim — EV-cap re-earn across paths)
`lootboxEvCapPacked` keyed per (player) with two windows tagged by level (Storage:1690-1738). `_lootboxEvUsedFor`
returns the `used` for `level` (0 if neither window is stamped); `_setLootboxEvUsedFor` writes into the
window stamped to `level`, else evicts the SMALLER-level window (never a live key — the live set is
{currentLevel, currentLevel+1}). The 10-ETH cap (`LOOTBOX_EV_BENEFIT_CAP`) binds per (player,level). All
EV-uplift paths (redemption, direct-open, Degenerette-recirc box) funnel into `_applyEvMultiplierWithCap`
(Lootbox:474) → `_setLootboxEvUsedFor` RMW, so the `used` for a live level is monotonic within that level
and cannot be reset to re-earn the uplift. (The cursor-lag two-window eviction edge is FC-389-01, owned by
389 — the ECON half here is the cap-binds-within-a-level confirmation.) **REFUTED** (cap cannot be reset
within a level across the composed paths).

### FC-392-03 (VERIFY-claim, INFO — faster decimator ramp)
The marginal streak gain (+150 bps/day vs +100) reaches the decimator streak-clamp (100) in ~33 active days
vs ~100 (the surface-map figure; decimator re-clamps streak to 100 inside its boost factor). This is the
documented "halve + uncap" rebalance of terminal-jackpot weight toward fast-ramping players — the coded
ramp matches the brief's intent. **BY-DESIGN** (VERIFY-claim confirmed; ramp speed is documented intent,
not a defect; ceiling unchanged).

### FC-392-10 (INFO — BoxSpin sentinel collision)
`BOX_BETID_SENTINEL = uint256(1) << 63` (Degenerette:1257); real bet nonces increment from 1
(`_boxBetId` ORs the sentinel into the box-spin betId, Degenerette:1268). A real bet nonce reaching bit 63
would require 2^63 ≈ 9.2e18 bets — unreachable over the game lifetime. The BoxSpin event-decode (sentinel
distinguishes box-spins from real bets) stays correct. **REFUTED-as-collision / INFO** (sentinel
unreachable).

### FC-392-14 (LOW — self-referral / circular-code capture)
`payAffiliate` is GAME-only (Affiliate:418). Self-referral guard: `resolved == sender ⇒ VAULT 0% kickback`
(Affiliate:439-444); an invalid/self/blank code locks to VAULT (noReferrer). The 75/20/5 winner-takes-all is
among affiliate/upline1/upline2 (the upline chain) — the buyer (sender) is NEVER in the distribution
(Affiliate §14 winner-takes-all roll). Chains terminate at VAULT (Affiliate:350-354). A chosen code cannot
route the upline1/upline2 (20/5%) slices back to the sender, and flipping `noReferrer` only switches between
VAULT/DGNRS 50/50 (no-referrer) and the upline distribution — neither lets the sender capture the affiliate
75% slice for a self-controlled address (the self-referral collapses to VAULT). Rewards are illiquid
flip-credit (`creditFlip`). **REFUTED** (no self-capture; intra-chain redistributive only).

### FC-392-15 (INFO — carried v62 affiliate-score asymmetry)
`affiliateBonusPointsBest` (Affiliate:720-730): `sum` accumulates `affiliateCoinEarned[lvl][player]`
monotonically over offsets 1..5; the early-break at `sum >= 25 ether` (the AFFILIATE_BONUS_MAX cap) returns
the SAME clamped result (sum only grows, the cap clamps at 25 ether) — no under-count. The GAME-only
`payAffiliate` access (Affiliate:418) removes the prior COIN-caller trust edge. The carried v62 asymmetry
finding-candidate is unchanged by these (the early-break is a gas optimization safe for monotonic
accumulation; the access narrowing reduces surface). **MONITOR/INFO** (asymmetry unchanged; no new defect —
the carried candidate's disposition is unchanged by the v63 changes).

### Council fold-in (NET 1, AFTER the independent pass)
Read `392-01-COUNCIL-NET.md` + `council/econ.gemini.txt` (codex skipped — usage-limit cap). Per-item
convergence/divergence vs NET 2:

| Item | NET-1 (gemini) | NET-2 (Claude, this doc) | Convergent? |
|---|---|---|---|
| ECON-01 accrual ceilings | VERIFIED SOUND | REFUTED (§1, per-surface bound) | ✓ convergent (no-finding) |
| ECON-02 redistributions | VERIFIED SOUND (split, 19,678, far/near) | REFUTED (§2, full arithmetic incl. variance 0.78595) | ✓ convergent (no-finding) |
| ECON-03 two EV changes | (implicit in SOUND) | REFUTED-as-divergence (§3, band + recycle in code) | ✓ convergent |
| **ECON-04 money pump** | **HIGH candidate** (floor+kicker = 110% loop) | **REFUTED** (§4, per-leg liquid accounting: kicker illiquid flip-gated ≈0.030·V, box sub-unity, value-in won-first) | **DIVERGENT** — NET 2 refutes the HIGH with the accounting gemini did not show |
| ECON-05 whale-pass supply | VERIFIED SOUND (one-per-bracket flag) | BY-DESIGN (§5, P(S=9)≈6.74e-8, ~99M opens, supply capped) | ✓ convergent (NET 2 adds the cost quant) |
| **ECON-06 streak pump** | **HIGH candidate** (afking↔manual same-day double) | **REFUTED** (§6, mask dedup + afking slot-0 skip + mutually-exclusive compute) | **DIVERGENT** — NET 2 refutes the HIGH at source |

The two gemini HIGH candidates (ECON-04 money pump, ECON-06 streak pump) are the prime divergences. NET 2
ran the dedicated per-leg accounting (§4) and the streak-machinery trace (§6) the council leads demanded,
and the skeptic dual-gate on each → both REFUTED at the frozen source. **codex was capped** (no second
source); a post-reset codex re-run of these two HIGH candidates is RECOMMENDED to second-source the
refutation (carry to 396 terminal council-on-refuted if still capped).

---

## §8 — Provisional verdict summary (NET 2)

| Item | Provisional verdict | Settling bound (§ + cite) |
|---|---|---|
| ECON-01 | REFUTED | §1 — every consumer saturates < 65_534 hard cap (40_000 EV / 30_500 ROI / streak-clamp-100) |
| ECON-02 | REFUTED | §2 — split 40/15/15/15/10/5; ×11/9=19,678 (8,855==8,855); far/near 1.000; variance 0.78595==0.786 |
| ECON-03 | REFUTED-as-divergence | §3 — band 9000-14500 @ 40,000 (Storage:1543-1547); recycle ≥3-ticket, drain deleted (Mint:1740) |
| ECON-04 | **REFUTED (no money pump)** | §4 — per-leg liquid accounting: kicker illiquid flip-gated ≈0.030·V, box sub-unity, presale box-restricted, value-in won-first, recursion depth 1 |
| ECON-05 / FC-392-07 | BY-DESIGN | §5 — P(S=9)≈6.74e-8, ~99M boxes/pass; global per-bracket flag caps supply (Degenerette:1325 == :751) |
| ECON-06 / FC-392-01 / -02 | **REFUTED (no streak pump)** | §6 — mask dedup (Quests:1708) + afking slot-0 skip (Quests:1745) + mutually-exclusive compute (Storage:2284); FC-392-01 level-quest +1 decay-corrected |
| FC-392-03 | BY-DESIGN | §7 — faster decimator ramp = documented "halve + uncap"; ceiling unchanged |
| FC-392-04 | MONITOR/INFO | §3(iii) — stale "8000-13500" comment (Lootbox:472-473); comment-only |
| FC-392-05 | REFUTED | §7 — 10-ETH cap per (player,level), monotonic within a level; evict-smaller-level (Storage:1712-1738) |
| FC-392-06 | REFUTED | §4 — same illiquid flip-credit gate; no positive loop with presale box-credit |
| FC-392-08 | (ECON half) BY-DESIGN; solvency→390, permissionless→393 | §4/§5 — recirc box EV bounded by 10-ETH cap; ETH-spin recirc depth 1; CEI/RMW solvency half owned by 390, permissionless-race half by 393 |
| FC-392-09 | REFUTED | §4 — aggregate box EV uplift bounded by the 10-ETH benefit cap |
| FC-392-10 | REFUTED/INFO | §7 — BOX_BETID_SENTINEL 1<<63 unreachable (2^63 bets) |
| FC-392-14 | REFUTED | §7 — self-referral → VAULT 0%; buyer never in distribution; intra-chain redistributive |
| FC-392-15 | MONITOR/INFO | §7 — monotonic early-break (no under-count); GAME-only access; asymmetry unchanged |

**NET 2 is on record for the ECON slice, independent of the council:** the bounded-accrual is swept
per-surface (§1); the EV-neutrality is re-verified in code with full arithmetic matched to the PAPER brief
(§2); the two EV changes are confirmed in code (§3); the money-pump composition is searched with per-leg
liquid wei/value accounting and the skeptic dual-gate (§4 — REFUTED, no HIGH); the whale-pass acquisition
cost is quantified P(S=9)≈6.74e-8 / ~99M boxes-per-pass with the per-bracket supply-cap proof (§5); the
streak-pump is traced at the frozen source with the skeptic dual-gate (§6 — REFUTED, no HIGH); the council
leads are folded in (§7) — the two gemini HIGH candidates are the prime divergences, both REFUTED with the
accounting/trace the leads demanded; codex-skip noted, post-reset re-run recommended.

`git diff a8b702a7 -- contracts/` EMPTY at the end of this task (read-only over the frozen subject; hardhat
never invoked; all source read via `git show a8b702a7:`).
