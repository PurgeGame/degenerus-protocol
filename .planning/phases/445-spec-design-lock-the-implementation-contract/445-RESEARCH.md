Anchors confirmed: append point at `:2393`/`:2394`, `TICKET_SCALE = 100` (so 4 whole tickets = `quantityScaled = 400`), and `whalePassClaims` already exists at `:1122`. Now assembling the reconciled RESEARCH.md.

# Phase 445 Research — v71.0 Foil Pack Design-Lock

## Executive Summary

The v71.0 Foil Pack coefficients are fully derived, exhaustively verified (V1/V2/V3 — zero material math errors), and build-ready. The **rarity PMF** is a tapered-linear-in-rare-rank boost: gold (color 7) takes the full multiplier `M` (`p_gold = (2/256)·M`), tiers 6→3 taper down with rare-rank weights `w = {7:5/5, 6:4/5, 5:3/5, 4:2/5, 3:1/5}`, and the three 25% commons (0/1/2) are the sole funding sink; resolve uses a `/15360 = 256×60` integer cutoff ladder that sums to exactly 15360 with all widths ≥ 0 for every integer `multBps ∈ [20000, 60000]` (gold lands exactly on `120·M`). The **`foilBoostBps(score)`** curve is a 4-anchor / 3-segment piecewise-linear bps function on the existing `ActivityCurveLib` knees — `FOIL_MIN_BPS=20000` (×2 @ score 0), `FOIL_K_POINTS=300 → FOIL_VA_BPS=50000` (×5), `ACTIVITY_SEG_B_KNEE_POINTS=500 → FOIL_VB_BPS=55000` (×5.5), `ACTIVITY_EFFECTIVE_CAP_POINTS=30000 → FOIL_MAX_BPS=60000` (×6) — monotone, saturating flat at ×6, honoring "~×5 @ 350" by shape (not pinned). **Calibration:** the match channel is provably **decoupled from the boost** (winning color is uniform 1/8, so the boost cancels: per-quadrant match `q = 1/64` for all M), yielding a realized **1.94 faces/pack/30d** that hits the D-05 ~2-face target at **every** score (M-invariant — no "calibrate-at-which-score" decision); gold-odds cross 10 normal tickets at **M ≈ 2.485** (multBps ≈ 24,854). **Storage:** one packed slot per player in `foilRecord` (`mapping(address => uint256)`) carrying 4 × 32-bit signatures + 16-bit frozen `multBps` + 24-bit level stamp = 168 bits (the E.6 superset form, **reconciled** over D.1's 24-bit/no-multBps variant per V3), with the stamp doubling as the per-raw-level cap flag (century idiom, auto-reset), plus a sparse `mapping(bytes32 => bool) foilMatchClaimed` double-claim marker — both tail-appended after `DegenerusGameStorage.sol:2393`, no slot moves. **Placement:** a **new `GAME_FOILPACK_MODULE`** (~8–11 KB body, ~13.5–16.5 KB EIP-170 headroom) plus two thin facade stubs (facade retains ~3.3–3.7 KB free of its measured 4,188 B).

## Open decisions for the planner / known risks

1. **[RECONCILED — adopt E.6] `foilRecord` packing: two layouts were stated; the planner must pin ONE.** V3 found Section D.1 specifies 24-bit signatures with **no `multBps`** stored, while Section E.6 specifies 4 × 32-bit packed-`uint32` signatures **plus** a 16-bit `multBps` (168 bits). The E.6 168-bit superset is **canonical** here: RARE-03 / MATCH-09 require the frozen `multBps` to live in the record (the jackpot resolve path and the match re-derivation both read it), and the full packed `uint32` per ticket matches the `packedTraitsFoil` output byte layout. **Canonical layout: `[stamp:24 | multBps:16 | sig0:32 | sig1:32 | sig2:32 | sig3:32]` = 168 bits ≤ 256.** Section D below uses this corrected form. (A 24-bit match-only signature is sufficient *if* the boosted jackpot traits are resolved on a separate path, but storing the full packed value is the robust superset and is chosen.)

2. **[CORRECTED — V3 DEFECT E-α, off-by-scale] Ticket queueing quantity must be scaled.** `_queueTicketsScaled`'s quantity arg is in `TICKET_SCALE = 100` units (verified `DegenerusGameStorage.sol:157, :663`). 4 whole foil tickets ⇒ pass **`400`**, not `4`. Section E.1 step 7 is corrected to `_queueTicketsScaled(buyer, _activeTicketLevel(), 400, false)`.

3. **[CORRECTED — V3 DEFECT F-α, count] Facade stub count.** The facade carries **65 external/public functions and 72 delegatecall sites**, not "48". The EIP-170 conclusion is unaffected (one extra stub ≈ 250–450 B against 4,188 B free); the count is corrected in Section F.

4. **[CORRECTED — V3 DEFECT F-β, anchor] ETH-cap clone source.** The cap+spill logic to clone is at `DegenerusGameDegeneretteModule.sol:877-915` (`maxEth` at `:889`, lootbox-resolve at `:915`), not `:402-446`. Corrected in Sections E.5 / F.2.

5. **[CORRECTED — V3 F.4 note] `whalePassClaims` already exists.** Verified at `DegenerusGameStorage.sol:1122` (`mapping(address => uint256)`). Do NOT re-declare it; the 4-of-4 tier does `whalePassClaims[player] += 1` against the existing slot.

6. **[NAMING — V3 DEFECT E-γ] Unify the claimed-marker identifier.** Sections cross-named it `foilClaimed` (E) and `foilMatchClaimed` (D). The SPEC must use ONE; this RESEARCH adopts **`foilMatchClaimed`**.

7. **[WORDING — V1 flag, non-blocking] PMF non-negativity binding case.** The PMF stays valid (all 8 tiers ≥ 0, Σ = 1) up to **M ≈ 8.8689** (the true common-zero-crossing), comfortably beyond the locked `[2, 6]` range. Section A's "binding case M = 6" should read "worst case **within** the locked `[2,6]` range"; the arithmetic and conclusion are already correct.

8. **[REPORTING — V2 note, non-blocking] Tier split is 87.9% / 12.1%**, not the spec's illustrative "~85% / ~12%" (2-of-4 / 3-of-4). Not materially off; no recalibration. The build-time comment should cite the realized **87.9%**.

9. **[REPORTING — V2 note, non-blocking] 4-of-4 per-pack rarity ≈ 1-in-69,906**, rarer than the spec's illustrative ≈1-in-300k context (the spec figure folds a narrower per-level draw window). EV-negligible either way and steer-proof. Documentation footnote only.

10. **[GOLD-HUNT vs MATCH-CHANNEL — design intelligence, NOT a tension] The two channels are fully decoupled.** The hypothesized tension (a boosted rare-tail PMF lowering match-collision odds) **does not materialize** because the winning color is uniform 1/8 — the boost cancels in the match channel. A high activity score buys a strictly better gold hunt *for free* with **zero** penalty to match faces. There is therefore no cross-channel trade-off to calibrate and no exploit to game via activity score. This is a desirable, steer-proof property (Section G.4).

11. **[IMPL-TIME MEASUREMENT — required] Exact EIP-170 after build.** All Section F sizes are measured on the *current* artifacts (no foil code yet). The real `GAME_FOILPACK_MODULE` and facade-after-stubs sizes MUST be re-measured on the post-IMPL build (HARD-REQ §6.7). Estimated module body 8–11 KB; estimated headroom 13.5–16.5 KB — to be confirmed.

12. **[IMPL ANCHOR — hero reconstruction] `claimFoilMatch(day)` must read `dailyHeroWagers[day-1]`** for the LIVE hero re-roll (the wager pool is day-lagged: `dailyIdx == D-1` when day `D`'s jackpot is processed; verified `DegenerusGameJackpotModule.sol:1290-1291`, set at AdvanceModule). Section E.3 captures this; it is reconstructible because `dailyHeroWagers` (`:1841`) is retained storage.

### REQ-ID coverage map

| Section | Requirements locked |
|---|---|
| A. Foil rarity PMF | RARE-01, RARE-02, RARE-04, (RARE-03 via the frozen `multBps` input) |
| B. Daily winning-trait distribution | MATCH-03, MATCH-09 (LIVE/HERO-FREE substrate), SEC-01 design basis |
| C. `foilBoostBps` curve | FOIL-05 (boost source), RARE-03 (frozen-at-buy), D-02 |
| D. Storage layout | FOIL-01 (per-level cap), MATCH-01, MATCH-02, MATCH-05, SEC-03, SEC-04 (layout goldens) |
| E. Entrypoints + match algorithm | FOIL-01..05, RARE-01/03/04, MATCH-01..10, SEC-01, SEC-02 design basis, SEC-03 |
| F. Module placement + EIP-170 | SEC-03 (shared storage), placement (D-04), HARD-REQ §6.7/§6.8 |
| G. Calibration | MATCH-06, MATCH-07, MATCH-08, MATCH-10, D-05 |

SEC-01 (steer-proof 4-of-4), SEC-02 (ETH ≤ 10% cap solvency), and SEC-04 (no-slot-move) are **attested downstream** at phases 448/449, but their **design basis is locked here**: SEC-01 in B/E.3 (HERO-FREE gate), SEC-02 in E.5/G (`ETH_WIN_CAP_BPS=1000` clamp + lootbox spill), SEC-04 in D.4/F.4 (append-only tail).

---

## A. Foil rarity PMF (tapered) — RARE-01/02/03/04

The new sibling producer `traitFromWordFoil(rnd, multBps)` / `packedTraitsFoil` clones the structure of `packedTraitsDegenerette` / `_degTrait` (`DegenerusTraitUtils.sol:201-223`): per-quadrant 6-bit `[CCC][SSS]`, quadrant bits OR'd in, 4 bytes packed into a `uint32`, symbol uniform `1/8` from `rnd>>32 & 7`. **Only the color stage changes** — the frozen `weightedColorBucket`/`traitFromWord`/`packedTraitsFromSeed` are untouched (RARE-01). The multiplier enters as `multBps` (the `foilBoostBps` output, `10000 = 1×`), frozen at buy from `cachedScore` and passed at resolve (RARE-03).

### The taper rule

Baseline color widths (verified at `weightedColorBucket`, `DegenerusTraitUtils.sol:115-126`), in `/256`:

| color | 0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 (gold) |
|---|---|---|---|---|---|---|---|---|
| base/256 | 64 | 64 | 64 | 32 | 16 | 8 | 6 | 2 |

A boost factor that is linear in the rare-rank, rarest tier taking the full multiplier `M`, each less-rare tier tapering toward `1×`:

```
boost(c) = 1 + (M − 1) · w_c          with rare-rank weights w_c ∈ [0,1]
  w_7 = 5/5   (gold = full ×M)
  w_6 = 4/5
  w_5 = 3/5
  w_4 = 2/5
  w_3 = 1/5   (least-rare boosted tier, still > 1× for any M > 1)
  w_0 = w_1 = w_2 = (funding sink — absorb all redistributed mass; not boosted)
```

Per-tier probability:

```
p_c   = (base_c / 256) · (1 + (M−1)·w_c)          for c ∈ {3,4,5,6,7}
p_0 = p_1 = p_2 = (192/256 − Δ) / 3               where Δ = Σ_{c∈{3..7}} p_c − Σ_{c∈{3..7}} base_c/256
```

This satisfies every D-03 constraint (all re-verified exactly in V1):
- **p_gold = baseline_gold · M** exactly: `w_7 = 1 ⇒ p_7 = (2/256)·M`. At `M=6 ⇒ 12/256 = 4.6875%` ✓.
- **Monotone-decreasing boost down the tail**: `w_7 > w_6 > w_5 > w_4 > w_3 > 0`, so `boost(7) > … > boost(3) > 1` for all `M > 1` (factors `[6,5,4,3,2]` at M=6, `[2,1.8,1.6,1.4,1.2]` at M=2). ✓
- **Commons 0/1/2 are the sole funding source** — only the three 25% commons shrink; tiers 3–7 only grow. ✓
- **Symbol uniform 1/8** — out of scope, unchanged (boost is color-tier ONLY, D-03). ✓

### Per-tier probabilities at M = 2.0, 2.5, 5.0, 6.0 (V1: all fractions reproduce exactly)

| color | M=2.0 | M=2.5 | M=5.0 | M=6.0 |
|---|---|---|---|---|
| 0 (common) | 419/1920 · 21.8229% | 259/1280 · 20.2344% | 59/480 · 12.2917% | 35/384 · 9.1146% |
| 1 (common) | 419/1920 · 21.8229% | 259/1280 · 20.2344% | 59/480 · 12.2917% | 35/384 · 9.1146% |
| 2 (common) | 419/1920 · 21.8229% | 259/1280 · 20.2344% | 59/480 · 12.2917% | 35/384 · 9.1146% |
| 3 | 3/20 · 15.0000% | 13/80 · 16.2500% | 9/40 · 22.5000% | 1/4 · 25.0000% |
| 4 | 7/80 · 8.7500% | 1/10 · 10.0000% | 13/80 · 16.2500% | 3/16 · 18.7500% |
| 5 | 1/20 · 5.0000% | 19/320 · 5.9375% | 17/160 · 10.6250% | 1/8 · 12.5000% |
| 6 | 27/640 · 4.2188% | 33/640 · 5.1562% | 63/640 · 9.8438% | 15/128 · 11.7188% |
| **7 (gold)** | **1/64 · 1.5625%** | **5/256 · 1.9531%** | **5/128 · 3.9062%** | **3/64 · 4.6875%** |
| **Σ** | **1.0000** | **1.0000** | **1.0000** | **1.0000** |

Gold equals `baseline×M` at each column (`0.78125% × M`), exactly as required. (M=2.5 is illustrative of the ~×2.5 tie point, not a pinned breakpoint.)

### Non-negativity proof (V1-corrected wording)

The redistributed mass `Δ(M)` (added to the rare tail, pulled from the commons):

```
Δ(M) = (M−1) · [ 32·(1/5) + 16·(2/5) + 8·(3/5) + 6·(4/5) + 2·(5/5) ] / 256
     = (M−1) · 24.4 / 256
```

**At the worst case WITHIN the locked [2,6] range (M = 6):** `Δ = 5 · 24.4 / 256 = 122/256`. The three-commons budget is `192/256`; since `122 < 192`, each common `= (192 − 122)/3 / 256 = 9.1146% > 0`. ✓ The PMF is valid (all 8 tiers ≥ 0, Σ = 1) at **every** M ∈ [2, 6]. *(V1 note: the actual common-zero-crossing is M ≈ 8.8689 — well beyond 6 — so the locked range has comfortable margin. "Worst case within [2,6]" is the precise framing; M=6 is the top of the validity range, not the zero-crossing.)*

### Integer cutoff ladder — use the `/15360` super-ladder (V1: PASS, exact at every multBps)

256-resolution is too coarse for the taper (at M=2 the commons are `55.867/256` and tiers 3–6 are `38.4 / 22.4 / 12.8 / 10.8`, none integral). **Build-ready fix:** compute cutoffs in a `/15360` ladder (`15360 = 256 × 60`; the `×60` clears both the `/5` taper denominator and the 3-way common split), then compare a scaled draw against the running sum (style-identical to `weightedColorBucket`'s `if (scaled < …) return …`). Per rare tier `c ∈ {3,4,5,6,7}`:

```
width15360[c] = base[c]·60 · (50000 + (multBps − 10000)·w5[c]) / 50000   // w5 = {3:1,4:2,5:3,6:4,7:5}
rare          = Σ width15360[c]
rem           = 15360 − rare
commons[0..2] = rem/3, with the (rem mod 3) residual handed to the first commons
```

**V1 verified exhaustively (40,001 grid points):** for every integer `multBps ∈ [20000, 60000]`, this ladder sums to exactly `15360` with all 8 widths ≥ 0, and gold equals `base7·60·M = 120·M` (i.e. exactly `baseline×M`), with **0 sum-mismatches and 0 negative widths**:

| multBps (M) | gold /15360 (= /256) | commons each /15360 | Σ |
|---|---|---|---|
| 20000 (×2.0) | 240 (= 4.0000/256) | 3352 | 15360 |
| 25000 (×2.5) | 300 (= 5.0000/256) | 3108 | 15360 |
| 50000 (×5.0) | 600 (= 10.0000/256) | 1888 | 15360 |
| 60000 (×6.0) | 720 (= 12.0000/256) | 1400 | 15360 |

The residual-to-commons rule keeps the sum exact at every continuous `multBps` (robust off-grid, not just at the grid points). RARE-01 preserved — the shared producers are untouched.

### Gold-odds anchors reproduce (sanity, not a constraint; V1: PASS)

`p_gold = baseline×M` over 16 boosted quadrants/pack vs 40 baseline quadrants from 10 normal tickets:
- **Score 0 (×2):** `1−(1−2/256·2)^16 = 22.27%` vs baseline `26.93%` → worse at the bottom ✓ (spec ≈22.3% vs 26.9%).
- **~×2.5:** `27.06%` → ≈ tie ✓.
- **Max (×6):** `53.61%` → ~2× baseline ✓ (spec 53.6%).

These follow from `p_gold` alone, unaffected by the chosen taper weights `w_6…w_3`.

---

## B. Daily winning-trait distribution (LIVE vs HERO-FREE) — MATCH-03/09, SEC-01 basis

### Producer: `getRandomTraits` — flat uniform 6-bit slice (NOT the heavy-tail ladder, NOT degenerette)

The daily winning set is generated by `JackpotBucketLib.getRandomTraits(uint256 rw)` (`JackpotBucketLib.sol:281-286`), called from `_rollWinningTraits` / `_rollWinningTraitsPair` (`DegenerusGameJackpotModule.sol:1767, 1787, 1792`):

```solidity
function getRandomTraits(uint256 rw) internal pure returns (uint8[4] memory w) {
    w[0] = uint8(rw & 0x3F);               // Quadrant 0: 0-63
    w[1] = 64 + uint8((rw >> 6) & 0x3F);   // Quadrant 1: 64-127
    w[2] = 128 + uint8((rw >> 12) & 0x3F); // Quadrant 2: 128-191
    w[3] = 192 + uint8((rw >> 18) & 0x3F); // Quadrant 3: 192-255
}
```

Each quadrant is a raw 6-bit slice `(rw >> 6q) & 0x3F`, packed `[QQ][CCC][SSS]`. Low 3 bits (`SSS`, symbol) and high 3 bits (`CCC`, color) are **both uniform 1/8**. This is materially different from the trait producers the foil **tickets** use: the winning set does **NOT** apply `weightedColorBucket` (heavy-tail) and does **NOT** apply `_degTrait` (near-uniform). It is a third model — pure uniform on all 6 bits.

### Per-quadrant winning COLOR distribution

| color c | p_win(color c) | note |
|---|---|---|
| 0–6 | 1/8 = 12.500% each | |
| 7 (gold) | 1/8 = 12.500% | NOT 0.781% — winning gold is far commoner than a ticket's gold |

`p_win(color)` is flat 1/8 across all 8 tiers; symbol uniform 1/8. **Net: per-quadrant exact `[color|symbol]` match probability ≈ 1/64 ≈ 1.5625%, independent of the foil rarity boost** — because the winning color is uniform, the ticket's boosted color distribution sums to 1 against a flat 1/8 weight and cancels. The rarity boost (D-02/D-03) does NOT change match-lottery odds — it only changes the tickets' own jackpot-gold participation (§1 of the spec). Key calibration fact for §G.

### LIVE vs HERO-FREE delta — precisely one component on one quadrant

`_applyHeroResult` (`DegenerusGameJackpotModule.sol:1316-1341`) overrides exactly one quadrant — the `heroQuadrant` chosen by `_rollHeroSymbol`. On that one quadrant it rewrites **both symbol and color**:
- **Symbol**: replaced by `heroSymbol` (the wager-board winner's symbol; player-steerable per §4).
- **Color**: re-sampled as `heroColor` from a *different (lower) bit-slice of the same word* (`randomWord & 7` for q0, `>>3 &7`, `>>6 &7`, `>>9 &7`), distinct from the base color's bits `[6q+3 .. 6q+5]`. Both are uniform 1/8, so the marginal is unchanged but the realized value generally differs — the override does NOT preserve the pre-override color.

| quadrant | HERO-FREE symbol | LIVE symbol |
|---|---|---|
| hero quadrant | uniform 1/8 (VRF lane) | `heroSymbol` point-mass when `hasHeroWinner`; falls back to uniform VRF symbol when `total==0` (no wagers → `_applyHeroResult` is a no-op) |
| other 3 quadrants | uniform 1/8 | uniform 1/8 (untouched) |

The **entire LIVE-vs-HERO-FREE delta is confined to one quadrant**. This matches §4 policy:
- **2-of-4 / 3-of-4 → match against LIVE** (hero edge KEPT; steered hero symbol can carry one quadrant).
- **4-of-4 → gated on HERO-FREE pure-VRF** (re-derive via `getRandomTraits(rngWordByDay[day])` without `_applyHeroResult`), so the whale-pass moonshot is steer-proof — a steered hero reaches at most 3-of-4.

### Main vs bonus — same distribution, independent draws (2 draws/day)

`_rollWinningTraitsPair` (`DegenerusGameJackpotModule.sol:1778-1795`): **Main** `r = rngWordByDay[day]`; **Bonus** `rBonus = EntropyLib.hash2(randWord, BONUS_TRAITS_TAG)` (keccak domain-separated → independent base traits/hero colors). **Shared:** ONE `_rollHeroSymbol(dailyIdx, randWord)` forces the **same hero `(quadrant, symbol)`** onto both; the hero *color* still differs (sampled per-roll). For the lottery: 2 i.i.d.-distributed winning sets/day (per-quadrant uniform 1/8 color and symbol), correlated only through the shared hero symbol; HERO-FREE versions are fully independent apart from the shared seed.

### Build-ready summary for the calibration

- `p_win(color c) = 1/8` ∀c; `p_win(symbol) = 1/8` ∀symbol — both draws, all quadrants.
- Per-quadrant exact match ≈ **1/64**, invariant under the foil rarity boost.
- LIVE delta = exactly one quadrant's symbol becomes a point mass (steered), bounded to 2-of-4 / 3-of-4 only.
- 4-of-4 uses HERO-FREE: naive single-draw 4-of-4 ≈ (1/64)^4 ≈ 1-in-1.68e7 (EV-negligible).

Sources: `JackpotBucketLib.sol:281-286`; `DegenerusGameJackpotModule.sol:1316-1341` (`_applyHeroResult`), `:1760-1795` (roll pair).

---

## C. `foilBoostBps(score)` curve — FOIL-05, RARE-03, D-02

### Decision (V1: PASS on all 9 curve checks)

A 4-anchor / 3-segment piecewise-linear bps curve `foilBoostBps(uint256 score) -> uint256`, modeled on the existing `decMultBps` / `centuryBps` idiom (`ActivityCurveLib.sol:42, :74`). Returns bps where `10000 = 1.0×`; range locked to **[20000, 60000] = [×2.0, ×6.0]**. Reuses the two existing shared knees — `ACTIVITY_SEG_B_KNEE_POINTS = 500` (`:26`) and `ACTIVITY_EFFECTIVE_CAP_POINTS = 30_000` (`:29`).

### Constants (append in `ActivityCurveLib`, mirroring the `MULT_*` / `CENTURY_*` blocks)

```solidity
// Foil-pack rarity boost (bps; 10000 = 1.0x). x2 floor at score 0 -> x6 ceiling at the cap.
uint256 internal constant FOIL_MIN_BPS = 20_000; // x2.0  at score 0 (low-activity floor)
uint256 internal constant FOIL_K_POINTS = 300;   // seg-A knee (in the existing 235/305 K band)
uint256 internal constant FOIL_VA_BPS  = 50_000; // x5.0  at K   (75% of the x2->x6 gain)
uint256 internal constant FOIL_VB_BPS  = 55_000; // x5.5  at the seg-B knee (87.5% of gain)
uint256 internal constant FOIL_MAX_BPS = 60_000; // x6.0  at the effective cap (saturates flat)
```

Anchors: `MIN→VA` over `[0, K]` (steep early ramp), `VA→VB` over `[K, 500]` (shallow middle), `VB→MAX` over `[500, 30000]` (long near-flat crawl), flat at `MAX` beyond — the identical shape signature as the two existing curves. `FOIL_K_POINTS = 300` sits inside the established seg-A-knee band (`MULT_K_POINTS = 235`, `CENTURY_K_POINTS = 305`). Total gain `= 40_000` bps; `VA`/`VB` deliver 75% / 87.5% of it at the two lower knees.

### Function (exact `decMultBps`-form interpolation)

```solidity
/// @notice Foil-pack rarity-boost multiplier in bps from a whole-point activity score.
/// @dev x2.0 at score 0 -> x6.0 at the effective cap; monotone non-decreasing; saturates flat.
///      Frozen at buy from cachedScore and applied at resolve (never live-read).
function foilBoostBps(uint256 score) internal pure returns (uint256) {
    if (score == 0) return FOIL_MIN_BPS;
    if (score >= ACTIVITY_EFFECTIVE_CAP_POINTS) return FOIL_MAX_BPS;
    if (score <= FOIL_K_POINTS) {
        return FOIL_MIN_BPS + (score * (FOIL_VA_BPS - FOIL_MIN_BPS)) / FOIL_K_POINTS;
    }
    if (score <= ACTIVITY_SEG_B_KNEE_POINTS) {
        return FOIL_VA_BPS +
            ((score - FOIL_K_POINTS) * (FOIL_VB_BPS - FOIL_VA_BPS)) /
            (ACTIVITY_SEG_B_KNEE_POINTS - FOIL_K_POINTS);
    }
    return FOIL_VB_BPS +
        ((score - ACTIVITY_SEG_B_KNEE_POINTS) * (FOIL_MAX_BPS - FOIL_VB_BPS)) /
        (ACTIVITY_EFFECTIVE_CAP_POINTS - ACTIVITY_SEG_B_KNEE_POINTS);
}
```

Per-segment closed forms (integer floor division, matching the existing curves):
- **Seg A** `0 < score ≤ 300`: `20000 + 100·score`
- **Seg B** `300 < score ≤ 500`: `50000 + 25·(score−300)`
- **Seg C** `500 < score < 30000`: `55000 + (score−500)·5000/29500`
- **Saturation** `score ≥ 30000`: `60000`

### Value table (exact, integer-floor; V1: all reproduce)

| score | bps | multiplier | segment |
|---|---|---|---|
| 0 | 20000 | ×2.0000 | floor |
| 50 | 25000 | ×2.5000 | A (spec ~tie anchor) |
| 100 | 30000 | ×3.0000 | A |
| 300 (K) | 50000 | ×5.0000 | A→B knee |
| 350 | 51250 | ×5.1250 | B (illustrative, NOT pinned) |
| 500 | 55000 | ×5.5000 | B knee |
| 5000 | 55762 | ×5.5762 | C |
| 30000 (max) | 60000 | ×6.0000 | cap |

### Invariant verification (V1: exhaustive over `[0, 30001]` + saturation tail)

- **Bounds** min 20000 / max 60000; never < ×2, never > ×6. ✓
- **Monotone** non-decreasing at every adjacent integer; 0 violations. ✓
- **Saturation** returns exactly 60000 for every `score ≥ 30000` (tested 30000, 30001, 50000, 1e9). ✓
- **Endpoints exact** via explicit guard branches (no interpolation rounding). ✓
- **"~×5 @ 350" honored by shape, 350 NOT pinned** — boundaries are `{0, 300, 500, 30000}`; ×5.0 lands at K=300. ✓
- **Spec "~tie @ ×2.5 (~score 30–50)"** — `foilBoostBps(50) = 25000` exactly. ✓

---

## D. Storage layout (`foilRecord`, cap flag, claimed marker) — FOIL-01, MATCH-01/02/05, SEC-03/04

### D.0 Grounded baseline facts (V3: all PASS)

| Fact | Source | Value |
|---|---|---|
| Canonical game level type | `DegenerusGameStorage.sol:236` | `uint24 public level = 0` (≤ 16,777,215) |
| `priceForLevel` key type | `PriceLookupLib.sol:21` | `priceForLevel(uint24 targetLevel)` |
| Day-keyed maps | `rngWordByDay:462`, `traitBurnTicket:442`, `ticketQueue:488`, `dailyHeroWagers:1841` | `mapping(uint24 => …)` — `day` is **uint24** |
| Retained daily RNG (claim re-derivation source) | `rngWordByDay:462` | `mapping(uint24 => uint256)` |
| Whale-pass deferred grant (**already exists**) | `whalePassClaims:1122` | `mapping(address => uint256)` |
| Century level-stamp idiom (the template) | `centuryBonusUsed:1857-1876` | `(level << 224) \| payload`, `_centuryUsedFor` returns payload only when `(packed >> 224) == level` (else 0 = auto-reset) |
| `TICKET_SCALE` | `:157, :663` | **100** (4 whole tickets = `quantityScaled = 400`) |
| **Append point (next free slot)** | `:2393` | `mapping(uint48 => address[]) internal boxPlayers;` is the LAST state var; closing `}` at `:2394`. New state appends after 2393. |

A signature carries 4 quadrants × full 6-bit `[CCC][SSS]` (color AND symbol; MATCH-03: "color-only does NOT count").

### D.1 `foilRecord` per player — RECONCILED canonical layout (V3 DEFECT D-α resolved → E.6 superset)

**Choice: one packed `uint256` per player, embedded level stamp, century idiom (NOT a `level => player` outer map). The record stores the full packed `uint32` per ticket PLUS the frozen `multBps`.**

```solidity
// Append after DegenerusGameStorage.sol:2393.

/// @dev Per-player foil-pack record, packed into ONE slot via the century stamp idiom.
///      buyFoilPack writes 4 packed-uint32 ticket signatures + the frozen 16-bit boost
///      multiplier, and stamps the raw buy level. _foilRecordFor returns the live data
///      only when the stamp equals the queried raw level (per-level auto-reset).
///      Layout (LSB->MSB): [0-31] sig0 | [32-63] sig1 | [64-95] sig2 | [96-127] sig3 |
///                         [128-143] multBps | [144-167] rawLevel stamp | [168-255] reserved (0).
mapping(address => uint256) internal foilRecord;

uint256 private constant _FOIL_SIG_MASK    = (uint256(1) << 32) - 1;   // 32-bit packed sig
uint256 private constant _FOIL_MULT_SHIFT  = 128;
uint256 private constant _FOIL_MULT_MASK   = (uint256(1) << 16) - 1;
uint256 private constant _FOIL_STAMP_SHIFT = 144;
uint256 private constant _FOIL_STAMP_MASK  = (uint256(1) << 24) - 1;
```

> **Stamp placement note:** the original D.1 derivation mirrored `centuryBonusUsed` exactly with the stamp at bit 224. With the wider E.6 record (168 bits of payload), the stamp is relocated to `[144-167]` so the four 32-bit sigs and the 16-bit `multBps` occupy `[0-143]`. The stamp is still a high-field self-stamp read via `(packed >> _FOIL_STAMP_SHIFT) & _FOIL_STAMP_MASK == lvl`, preserving the auto-reset semantics; only the bit offsets differ from `centuryBonusUsed`. (IMPL may instead keep the stamp at bit 224 and place `multBps` at `[128-143]`, sigs at `[0-127]` — either is one slot, ≤ 256 bits; pin ONE in the SPEC.)

```solidity
/// @dev The four live packed signatures + frozen multBps for `player` at raw `lvl`,
///      or (false, 0, [0,0,0,0]) when the stored stamp belongs to a prior level.
function _foilRecordFor(address player, uint256 lvl)
    internal view returns (bool present, uint16 multBps, uint32[4] memory sigs)
{
    uint256 packed = foilRecord[player];
    if (((packed >> _FOIL_STAMP_SHIFT) & _FOIL_STAMP_MASK) != lvl) return (false, 0, sigs);
    sigs[0] = uint32(packed & _FOIL_SIG_MASK);
    sigs[1] = uint32((packed >> 32) & _FOIL_SIG_MASK);
    sigs[2] = uint32((packed >> 64) & _FOIL_SIG_MASK);
    sigs[3] = uint32((packed >> 96) & _FOIL_SIG_MASK);
    multBps = uint16((packed >> _FOIL_MULT_SHIFT) & _FOIL_MULT_MASK);
    present = true;
}
```

**Bit budget (single slot):** 4 × 32 (sigs) + 16 (`multBps`) + 24 (stamp) = **168 bits ≤ 256**. One SSTORE on buy, one SLOAD on claim.

**Key-shape justification (V3: PASS):**
- **Per-level auto-reset for free** — the embedded stamp makes a prior level's record read absent, identical to `centuryBonusUsed`; one cold slot per player, not per player-per-level.
- **Griefing-resistance (§5 "records persist per-level", MATCH-05)** — a record written at level *L* is only overwritten when the SAME player buys again at a later level (gated by `level++`). It is never touched by `advanceGame` or another player. A fast `level++` does NOT strand an unclaimed match: the sigs + stamp `L` persist, and `claimFoilMatch` re-derives eligibility from the stamp `L` and the retained `rngWordByDay[day]`, so matches for days within *L* stay claimable until the player's NEXT foil buy. The whole-level window (MATCH-02) is read from the stamp, not a live `level` compare.
  - *IMPL caveat (not a layout change):* one record slot per player means buying at *L+1* overwrites *L*'s sigs. Acceptable under §5; the claimed marker (D.3) keys by `level`, so it never confuses *L* and *L+1*. A `mapping(level=>mapping(address=>uint256))` variant (additive widening, no reorder) would let *L*'s unclaimed matches survive an *L+1* buy — the single-slot form is the §5-compliant minimum and is chosen.

### D.2 Per-level one-pack cap flag — folded into `foilRecord` (no separate slot; V3: PASS)

The one-foil-pack-per-raw-level cap (FOIL-01) needs **no additional storage**: presence in `foilRecord` at the current raw level *is* the cap.

```solidity
/// @dev True if `player` has already bought their one foil pack this raw level.
function _foilBoughtThisLevel(address player, uint256 lvl) internal view returns (bool) {
    return ((foilRecord[player] >> _FOIL_STAMP_SHIFT) & _FOIL_STAMP_MASK) == lvl;
}
```

`buyFoilPack` reverts when `_foilBoughtThisLevel(msg.sender, level)`, then the record write stamps the current `level`. A stale stamp reads "not bought" (fresh allowance at the new level), exactly the century-flag semantics. Sigs (low bits), `multBps` (mid), and the cap (stamp, high bits) share one slot → no "bought but no record" / "record but no cap" desync. Keyed on **raw `level`** (§1), never `_activeTicketLevel()`.

### D.3 Sparse claimed marker — `mapping(bytes32 => bool) foilMatchClaimed` (V3: PASS, collision-free)

```solidity
/// @dev Sparse claimed marker for foil match settlement. Key =
///      keccak256(abi.encode(player, level, day, drawKind, ticketIndex)). Each tuple is
///      claimable at most once, so a ticket is claimed independently against main
///      (drawKind 0) and bonus (drawKind 1) of each eligible day, but never twice per draw.
mapping(bytes32 => bool) internal foilMatchClaimed;
```

**Key composition (MATCH-05 / §3):** `keccak256(abi.encode(player, uint256(level), uint256(day), uint256(drawKind), uint256(ticketIndex)))` — five distinct positional `abi.encode` fields (each 32-byte padded; no concatenation ambiguity). `player` isolates callers; `level` (raw `uint24`) binds the marker to the record's stamp (no *L*/*L+1* replay); `day` spans the whole-level window (MATCH-02); `drawKind ∈ {0=main,1=bonus}` (2 draws/day); `ticketIndex ∈ {0..3}` (4 independent tickets, MATCH-04). `claimFoilMatch` reverts if set, pays the tier, then sets `foilMatchClaimed[key] = true` (CEI: mark before any external transfer). **Sparse** — only realized winning claims write a slot; no draw-time scan, so `advanceGame` stays flat.

### D.4 No-collision / no-reorder attestation (V3: PASS, SEC-04)

- **Append-only at the tail.** All additions go after `boxPlayers` (`:2393`), before `:2394`. No existing declaration moved/retyped/reordered/removed.
- **Constants consume no slots.** `_FOIL_*` masks/shifts are `private constant` (inlined, like `_CENTURY_USED_MASK:1864`); `internal` helpers have no storage footprint.
- **Two new base mapping slots** (`foilRecord`, `foilMatchClaimed`) take the next two slots after `boxPlayers`'s. All prior slot indices unchanged → layout goldens byte-preserved (SEC-04).
- **Storage lives only in `DegenerusGameStorage`** (delegatecall-shared base; SEC-03), never in the foil module or facade.
- **Net cost:** 2 new base mapping slots. `foilRecord` = 1 packed slot per player who ever bought (cap + sigs + `multBps` co-resident, no separate cap slot). `foilMatchClaimed` = 1 slot per realized winning claim (sparse).

---

## E. Entrypoint signatures + match algorithm — FOIL-01..05, RARE-01/03/04, MATCH-01..10, SEC-01, SEC-02 basis, SEC-03

> All `file:line` anchors verified (V3). "Foil signature" = a packed `uint32` `[QQ][CCC][SSS]×4` in the **same byte layout** as `packedTraitsFromSeed`/`packWinningTraits` (so the match predicate is a direct byte compare). `level` = raw `uint24 public level` (`:236`); `_activeTicketLevel()` = the rng-lock-aware variant for ticket queueing.

### E.1 `buyFoilPack()` — facade stub + module body

**Facade stub (thin, on `DegenerusGame`; pattern = `buyPresaleBox` `DegenerusGame.sol:614-629`):**
```solidity
function buyFoilPack() external payable {
    // _resolvePlayer -> encodeWithSelector -> GAME_FOILPACK_MODULE.delegatecall(msg.data) -> _revertDelegate
}
```
No params: the pack is fully determined by `(msg.sender, level, msg.value)` — one fixed SKU (4 tickets) at one fixed price/level. `payable` carries the fresh-ETH leg; a zero-value call is the claimable-funded path.

**Module body `_buyFoilPack(address buyer, uint256 ethSent)`, in order:**

1. **Liveness / phase gate** — `if (_livenessTriggered()) revert E();` (same guard `_queueTicketsScaled` enforces at `:649`).
2. **One-per-RAW-level cap (FOIL-01)** — `uint24 lvl = level; if (_foilBoughtThisLevel(buyer, lvl)) revert E();` (stale stamp reads "not bought", auto-reset). The stamp write happens in step 6 (after price settles) so a reverting buy leaves no flag.
3. **Price + payment classification (FOIL-02, FOIL-03)** — `uint256 cost = 10 * PriceLookupLib.priceForLevel(lvl);`. Reuse the `_processMintPayment` accounting shape (`DegenerusGameMintModule.sol:236-299`) but **REJECT the afking leg** via the residual:
   - `uint256 ethUsed = ethSent < cost ? ethSent : cost;` (overpay ignored).
   - `uint256 remaining = cost - ethUsed;`
   - If `remaining != 0`: `uint256 claimable = _claimableOf(buyer); uint256 avail = claimable > 1 ? claimable - 1 : 0; if (remaining > avail) revert E();` ← **this `revert E()` IS the afking-rejection guard** (the normal path silently taps afking at `:288`; the foil path requires `claimableUsed == remaining`).
   - **Storage write:** `_debitClaimable(buyer, remaining); claimablePool -= uint128(remaining);` (`_debitClaimable:941` touches only the claimable half — never `_debitAfking:956`; the `claimablePool` decrement is a separate statement, per the `:898-899` precedent).
4. **Pool split — fork to 75/25 (FOIL-04)** — new constant **`FOIL_TO_FUTURE_BPS = 2500`** (NOT the shared `PURCHASE_TO_FUTURE_BPS = 1000`):
   - `uint256 prizeContribution = cost; uint256 futureShare = (prizeContribution * FOIL_TO_FUTURE_BPS)/10_000; uint256 nextShare = prizeContribution - futureShare;`
   - **Storage write** via the frozen/unfrozen branch of `_recordMintPayment` (`DegenerusGameMintModule.sol:201-217`): `prizePoolFrozen` → `_setPendingPools(...)`, else `_setPrizePools(...)`. Only the bps constant is forked; routing reused verbatim.
5. **Boost freeze (RARE-03)** — compute the buy-time score ONCE → bps multiplier, frozen:
   - `score = _playerActivityScore(buyer, …)` — the **same `_playerActivityScore` source** the mint path freezes as `cachedScore` (`DegenerusGameMintModule.sol:1709`; def `DegenerusGameMintStreakUtils.sol:267`, returns whole points).
   - `uint16 multBps = uint16(ActivityCurveLib.foilBoostBps(score));` (`20000..60000`). Frozen into `foilRecord` (step 6), **never live-read** at resolve.
6. **Roll 4 foil signatures + write the record (MATCH-01, RARE-01/04)** — the boost is applied HERE, at buy:
   - `uint256 seed = uint256(keccak256(abi.encode(buyer, lvl, FOIL_SEED_TAG)));` (deterministic/frozen, no live RNG; `FOIL_SEED_TAG` a new domain constant).
   - For `i in 0..3`: `uint32 sig_i = DegenerusTraitUtils.packedTraitsFoil(uint256(keccak256(abi.encode(seed, i))), multBps);` (E.4 sibling of `packedTraitsDegenerette` `:201`).
   - **Storage write:** `foilRecord[buyer] = pack(stamp=lvl, multBps, sig0..3);` — single SSTORE (D.1 layout). This is **both** the per-level cap flag (step 2 reads its stamp) and the frozen signature/boost record.
7. **Enter the 4 tickets into the REGULAR jackpot (FOIL-05)** — at the active ticket level so they share `traitBurnTicket[level][traitId]` eligibility (`:442`):
   - **`_queueTicketsScaled(buyer, _activeTicketLevel(), 400, false);`** — **CORRECTED (V3 E-α): pass `400`, not `4`**, because the 3rd arg is `quantityScaled` in `TICKET_SCALE = 100` units (`:157, :663`); 4 whole tickets ⇒ `400`. **External effect:** emits `TicketsQueuedScaled`; pushes `ticketQueue[wk]`; writes `ticketsOwedPacked[wk][buyer]`.
   - **Trait-resolution note for IMPL:** the queue-resolution path that today calls `packedTraitsFromSeed` (heavy-tail) must, for foil-owed entries, resolve via `packedTraitsFoil(seed, multBps)` so the on-chain jackpot traits carry boosted gold odds (real `color==7`). The frozen `multBps` is the input; the v70-frozen producers are NOT edited (foil entries route to the sibling). Mechanism (parallel foil-owed queue vs per-entry boost tag) is an IMPL-446 detail; the SPEC fixes the producer = `packedTraitsFoil` and multiplier = frozen `multBps`.
8. **No FLIP/WWXRP/whale-pass mint at buy.** Pure cost-in; rewards flow only through `claimFoilMatch`.

**External calls in `buyFoilPack`:** none beyond the delegatecall facade→module. All effects are local storage writes.

### E.2 `claimFoilMatch(uint256 day, uint256 ticketIndex, uint8 drawKind)` — pull/claim

**Signature decision:** keyed **per `(day, drawKind, ticketIndex)`** (`drawKind ∈ {0=main,1=bonus}`, taken explicitly — no internal loop). 2 draws × 4 tickets ⇒ 8 independent claimables/day; the sparse marker is 1:1 with the claim, keeping gas bounded. (A multi-claim batcher is an additive, out-of-scope nicety.)

```solidity
function claimFoilMatch(uint256 day, uint256 ticketIndex, uint8 drawKind) external;
```

**Body, in order:**
1. **Bounds + record load** — `require(ticketIndex < 4); require(drawKind < 2);` Load `(present, multBps, sigs) = _foilRecordFor(msg.sender, recLevel)`; `require(present)`. Records persist per-level (MATCH-05): keyed by player, stamped `recLevel`; a fast `level++` cannot grief (not auto-wiped until the SAME player re-buys, itself gated by E.1 step 2).
2. **Eligibility window (MATCH-02)** — `require(day` falls within `recLevel`'s draw-day span`)`. Eligible the WHOLE level (day's level-of-record == `recLevel`).
3. **RNG availability** — `uint256 rw = rngWordByDay[uint24(day)]; require(rw != 0);` (`:462`; retained daily VRF — re-derivation source, never live-read).
4. **Double-claim guard (MATCH-05)** — `bytes32 mk = keccak256(abi.encode(msg.sender, recLevel, day, drawKind, ticketIndex)); require(!foilMatchClaimed[mk]); foilMatchClaimed[mk] = true;` — set BEFORE any payout (CEI).
5. **Re-derive the day's winning sets (E.3)** — LIVE (hero-overridden) and HERO-FREE pure-VRF for the requested `drawKind`.
6. **Count positional matches (MATCH-03)** — quadrant `q` matches iff `foilQuad_q == winQuad_q` as full 6-bit `[CCC][SSS]` (color AND symbol; **color-only does NOT count**; a positional/wrong-quadrant match does NOT count — both sides carry `[QQ]`). Compute `liveCount` (vs LIVE) and `heroFreeCount` (vs HERO-FREE).
7. **Tier resolution (MATCH-09 — steer-proof gate):**
   - **2-of-4 / 3-of-4 off `liveCount`** (bounded hero edge KEPT): `if (liveCount==3) tier=3; else if (liveCount==2) tier=2;`
   - **4-of-4 ONLY if `heroFreeCount==4`** (steer-proof): a steered hero shifts at most one quadrant's symbol on LIVE → can reach at most 3-of-4, never `heroFreeCount==4`. (If `liveCount==4` only via the hero override but `heroFreeCount==3`, it pays the **3-of-4** tier; the 4-of-4 gate is `heroFreeCount`, never `liveCount`.)
   - `if (tier == 0) revert E();`
8. **Pay the tier (E.5)** via the isolated foil schedule; for tier 4 also `whalePassClaims[msg.sender] += 1` (`:1122`, the EXISTING slot).

### E.3 The crux — winning-set re-derivation (LIVE vs HERO-FREE; V3: byte-faithful, PASS)

Re-derive from `rw = rngWordByDay[day]`, mirroring `_rollWinningTraits` (`DegenerusGameJackpotModule.sol:1760-1769`):

```
// per-drawKind base word (matches :1764-1766):
r = (drawKind == 1) ? EntropyLib.hash2(rw, uint256(BONUS_TRAITS_TAG)) : rw;

// 1. HERO-FREE pure-VRF set (no _applyHeroResult):
uint8[4] heroFreeW = JackpotBucketLib.getRandomTraits(r);          // :281
uint32 heroFreeSet = JackpotBucketLib.packWinningTraits(heroFreeW);

// 2. LIVE (hero-overridden) set:
(bool hasHero, uint8 hQ, uint8 hSym) = _rollHeroSymbol(dailyIdxFor(day), rw);  // hero entropy = rw (:1768)
uint8[4] liveW = heroFreeW;
_applyHeroResult(liveW, r, hasHero, hQ, hSym);                     // overrides liveW[hQ] only (:1316-1341)
uint32 liveSet = JackpotBucketLib.packWinningTraits(liveW);
```

Critical grounding:
- **HERO-FREE = pre-override `getRandomTraits(r)`** (`:281-286`, flat 6-bit slices) — the un-steerable substrate; `heroFreeW[hQ]` still holds the VRF symbol, never the steered one.
- **LIVE = HERO-FREE with `_applyHeroResult`** (`:1316-1341`) — overwrites only `w[heroQuadrant]` (color from `r`'s low bits, symbol = steered `heroSymbol`); every non-hero quadrant is byte-identical.
- **Hero entropy is `rw`** (unsalted day word) on BOTH main and bonus (`_rollWinningTraitsPair` shares ONE `_rollHeroSymbol(dailyIdx, randWord)` at `:1785`); only the base word `r` differs (main `rw` / bonus `hash2(rw, BONUS_TRAITS_TAG)`).
- **`dailyIdxFor(day)` — CRITICAL IMPL ANCHOR (V3):** the override reads `dailyHeroWagers[dailyIdx]` where `dailyIdx == day-1` (the prior-day wager pool; verified `:1290-1291`, set at AdvanceModule). So `claimFoilMatch(D)` MUST read `dailyHeroWagers[D-1]`. The pool (`:1841`) is retained → fully reconstructible.

**Consequence (SEC-01):** a steerer controls only `heroSymbol` of `liveW[hQ]`; `heroFreeCount` is on pure VRF (untouchable). Max steered contribution = `+1` to `liveCount`; the 4-of-4 whale-pass moonshot (gated on `heroFreeCount==4`) is un-steerable and non-stackable.

### E.4 `foilBoostBps` + `packedTraitsFoil` (signatures only — coefficients in §C/§A)

```solidity
// in ActivityCurveLib (modeled on decMultBps :42-61 / centuryBps :74-90):
function foilBoostBps(uint256 score) internal pure returns (uint256);   // 20000..60000

// in DegenerusTraitUtils (clone of packedTraitsDegenerette/_degTrait :201-223;
//   v70-frozen weightedColorBucket/traitFromWord/packedTraitsFromSeed untouched):
function traitFromWordFoil(uint64 rnd, uint256 multBps) internal pure returns (uint8); // tapered color (A); symbol uniform 1/8
function packedTraitsFoil(uint256 rand, uint256 multBps) internal pure returns (uint32); // 4x quadrant pack, identical [QQ][CCC][SSS]
```

### E.5 Isolated foil payout schedule (MATCH-04/06/07/08, SEC-02 basis)

The foil claim owns its tier→faces schedule; it MUST NOT route through the EV-flat Degenerette `quickPlay` tables (those become +EV under boosted foil gold). `1 face = 1,000 FLIP = priceForLevel(recLevel) ETH`.

**Base faces by tier (locked, D-05):** 2-of-4 → 5 faces; 3-of-4 → 65 faces; 4-of-4 → `whalePassClaims += 1` PLUS a bonus spin (~1,000 faces).

**Disjoint entropy lanes off `rw` (MATCH-08)** — three separate keccak domains, independent of each other AND of the match lane:
```
matchLane     = (consumed in E.3: getRandomTraits(r) bit-slices + _rollHeroSymbol keccak)
magnitudeLane = uint256(keccak256(abi.encode(rw, day, drawKind, ticketIndex, FOIL_MAG_TAG)))
currencyLane  = uint256(keccak256(abi.encode(rw, day, drawKind, ticketIndex, FOIL_CCY_TAG)))
```
Per-tuple salting independently rolls each of the 8 daily claim-units. `FOIL_MAG_TAG ≠ FOIL_CCY_TAG ≠ BONUS_TRAITS_TAG ≠ FLIP_JACKPOT_TAG` — distinct domains ⇒ lanes provably disjoint.

**Currency split (40 FLIP / 40 ETH / 20 WWXRP, every spin, all tiers):**
```
uint256 c = currencyLane % 100;
if (c < 40)      currency = FLIP;   // [0,40)
else if (c < 80) currency = ETH;    // [40,80)
else             currency = WWXRP;  // [80,100)
```
**Magnitude:** `faces = baseFacesForTier` (the locked D-05 base values are the calibration target; §G confirms ≈2 faces/pack/30d). Convert: FLIP/WWXRP `= faces * 1000e18`; ETH `= faces * priceForLevel(recLevel)`.

**Payout effects by currency:**
- **FLIP (40%)** — `coin.mintForGame(msg.sender, flipAmount)` (`IDegenerusCoin.sol:20`). Free mint, no solvency impact.
- **ETH (40%)** — the existing capped-spin path: clamp `ethShare` to `ETH_WIN_CAP_BPS = 1000` (10% of `futurePrizePool`); **clone source CORRECTED (V3 F-β): `DegenerusGameDegeneretteModule.sol:877-915`** (`maxEth` at `:889`, lootbox-resolve at `:915`). Over-cap spills to the lootbox; credit the capped ETH via `_creditClaimable(msg.sender, cappedEth)` (`:933`) and decrement `runningFuture`/`pendingFuture` exactly as `:884-903`. Structurally solvent: `ethShare ≤ 10%·pool` (SEC-02). **Writes:** prize-pool decrement + `balancesPacked[msg.sender]` claimable-half + `claimablePool`; **external call:** lootbox resolve on spill.
- **WWXRP (20%)** — `wwxrp.mintPrize(msg.sender, wwxrpAmount)` (`WrappedWrappedXRP.sol:229`). Free mint, no solvency impact.

**4-of-4 extra (MATCH-07):** in addition to the bonus spin, `whalePassClaims[msg.sender] += 1` (`:1122`) — pool-neutral deferred grant (settled later via `DegenerusGameWhaleModule.sol:991-995`). No ETH leaves at claim for the pass leg.

**External calls in `claimFoilMatch`:** at most one of `{coin.mintForGame, wwxrp.mintPrize}` plus, on the ETH lane, the claimable credit + a possible lootbox-resolve delegatecall on the cap spill. All AFTER `foilMatchClaimed[mk] = true` (CEI).

### E.6 New storage to append (SEC-03) — see Section D for the canonical packed layout

- `mapping(address => uint256) internal foilRecord;` — one packed slot per player: `[ sig0:32 | sig1:32 | sig2:32 | sig3:32 | multBps:16 | levelStamp:24 ]` = **168 bits ≤ 256** (the reconciled superset; the 24-bit stamp doubles as the per-RAW-level cap flag + auto-reset).
- `mapping(bytes32 => bool) internal foilMatchClaimed;` — the sparse `(player, level, day, drawKind, ticketIndex)` double-claim marker.

New constants: `FOIL_TO_FUTURE_BPS = 2500`, `FOIL_SEED_TAG`, `FOIL_MAG_TAG`, `FOIL_CCY_TAG`, plus `foilBoostBps`'s segment bps (in `ActivityCurveLib`, §C). `whalePassClaims` already exists (`:1122`) — do NOT re-declare. Module placement (D-04) decided by §F; this section fixes signatures/effects regardless of host.

---

## F. Module placement + EIP-170 — SEC-03, placement (D-04)

### F.1 Measured deployed-bytecode sizes (V3: every figure matches to the byte)

Read from `forge-out/` (`foundry.toml`: `via_ir = true`, `optimizer_runs = 1000`, `evm_version = "osaka"`, `solc 0.8.34`). Sizes = `len(deployedBytecode.object)/2`; EIP-170 limit = 24,576 B.

| Contract | Deployed bytes | Headroom | Foil candidate? |
|---|---:|---:|---|
| **DegenerusGame (facade)** | **20,388** | **4,188** | facade stub only |
| **DegenerusGameMintModule** | **23,460** | **1,116** | NO (SEC-03; near-full) |
| DegenerusGameJackpotModule | 17,724 | 6,852 | roomy |
| DegenerusGameAdvanceModule | 19,056 | 5,520 | spine — avoid |
| DegenerusGameBingoModule | 3,161 | 21,415 | very roomy |
| DegenerusGameBoonModule | 3,760 | 20,816 | very roomy |
| DegenerusGameDecimatorModule | 11,006 | 13,570 | roomy |
| DegenerusGameDegeneretteModule | 13,766 | 10,810 | roomy (spin sibling) |
| DegenerusGameGameOverModule | 4,721 | 19,855 | very roomy |
| DegenerusGameLootboxModule | 19,690 | 4,886 | tight |
| DegenerusGameWhaleModule | 15,232 | 9,344 | roomy (whale-pass sibling) |
| GameAfkingModule | 17,757 | 6,819 | roomy |

Facade 4,188 B free, MintModule 1,116 B free (confirmed). MintModule excluded by SEC-03 and physically (no room).

### F.2 Foil body size estimate

The two library pieces are `internal pure` and inline into their caller:
- **Sibling producer** `traitFromWordFoil`/`packedTraitsFoil` (clone of `packedTraitsDegenerette`/`_degTrait` `:201-223`) + the `multBps`-scaled tapered cutoff table — **~0.4–0.7 KB inlined** per call site.
- **`foilBoostBps(score)`** (4-segment bps curve) — **~0.2–0.4 KB inlined**.

The deployed bulk lives in three module bodies:
- **`buyFoilPack`** (cap check, `10 × priceForLevel`, 75/25 split fork, freeze `cachedScore→multBps`, derive+store 4 sigs, queue 400 scaled tickets) — **~2.5–3.5 KB.**
- **`claimFoilMatch`** (re-derive winning traits, HERO-FREE branch for 4-of-4, exact 6-bit positional count, tier select, sparse marker) — **~2.5–3.5 KB.**
- **Isolated spin payout** (own tier→faces table, 40/40/20 split with the `ETH_WIN_CAP_BPS=1000` cap + lootbox spill cloned from `DegenerusGameDegeneretteModule.sol:877-915`, `coin.mintForGame`/`wwxrp.mintPrize`, `whalePassClaims += 1`) — **~3–4 KB.**

**Total estimated foil body ≈ 8–11 KB deployed.**

### F.3 Recommendation: a NEW `GAME_FOILPACK_MODULE` (V3: PASS)

An ~8–11 KB body does not fit any single roomy module with comfortable margin + EIP-170 safety, and every usable candidate (Jackpot/Whale/Degenerette/Afking/Decimator) is a live audited spine whose re-audit + slither/layout-golden re-pass cost exceeds standing up a clean module. The very-roomy modules (Bingo/Boon/GameOver) could absorb it physically but would couple an unrelated payable purchase + lottery feature into unrelated bodies.

**Recommend a new `GAME_FOILPACK_MODULE`** (mirrors the existing 12-module dispatch). The body starts at 0 → ~8–11 KB lands inside a fresh 24,576-cap contract with **~13.5–16.5 KB headroom**.

**Headroom math:**
- New `GAME_FOILPACK_MODULE`: ~8–11 KB → **13.5–16.5 KB free**. No EIP-170 risk.
- Facade stubs: `payable buyFoilPack()` + `claimFoilMatch(day, ticketIndex, drawKind)`. Each ~250–450 B; two ≈ **0.5–0.9 KB** against 4,188 B free → facade lands at **~3.3–3.7 KB free**. The facade currently carries **65 external/public functions and 72 delegatecall sites** (**CORRECTED V3 F-α; was stated "48"**) in 2,480 lines at 20,388 B — the conclusion is unaffected.
- `ContractAddresses.sol`: one new `address internal constant GAME_FOILPACK_MODULE = …;` (existing 12 `GAME_*_MODULE` constants at `:13-35`); negligible facade impact.

### F.4 Storage & facade-thinness confirmation (V3: PASS)

- **New storage appends in `DegenerusGameStorage.sol` (delegatecall-shared), never in a module.** Clean tail append after `boxPlayers` (`:2393`): `foilRecord` (one slot per `(player)`, century-stamped, holding 4 × 32-bit sigs + 16-bit `multBps` + 24-bit stamp) and the sparse `foilMatchClaimed` (`mapping(bytes32 => bool)`). Appends preserve all existing slot assignments — goldens shift only by tail additions, no slot moves (HARD-REQ §6.8 / SEC-04).
- **Level-stamp idiom confirmed** (`DegenerusGameStorage.sol:1857-1876`) for the one-per-raw-level flag + auto-reset.
- **Facade stub is thin** — identical `resolve → encodeWithSelector → GAME_*_MODULE.delegatecall(msg.data) → _revertDelegate` pattern (template `buyPresaleBox` `DegenerusGame.sol:614-629`); all foil logic in `GAME_FOILPACK_MODULE`, all state in `DegenerusGameStorage`.
- **`whalePassClaims` ALREADY exists (`:1122`)** — **CORRECTED (V3): do NOT add it.** The earlier "optionally add if not present" note is removed.

**Net:** new `GAME_FOILPACK_MODULE` (~13.5–16.5 KB headroom) + two thin facade stubs (facade retains ~3.3–3.7 KB) + tail-appended shared storage. EIP-170 fits with wide margin on all three; **re-measure on the real post-IMPL build (HARD-REQ §6.7).**

---

## G. Calibration — MATCH-06/07/08/10, D-05

All numbers are closed-form exact binomials (a Monte-Carlo is unnecessary because the per-quadrant match probability collapses to a constant; V2 independently reproduced every figure to full precision, 0% Δ). Grounded against the verified producers: foil ticket color = boosted heavy-tail, foil symbol uniform `1/8`; winning set = `getRandomTraits` uniform `1/8` × `1/8` (`JackpotBucketLib.sol:281-286`); hero override on exactly one quadrant (`DegenerusGameJackpotModule.sol:1316-1341`).

### G.1 — Per-quadrant exact match probability `q(M)` (LIVE, non-hero quadrants)

```
q(M) = (1/8)·Σ_c p_foil(c|M)·p_win(c) = (1/8)·(1/8)·Σ_c p_foil(c|M) = (1/8)·(1/8)·1 = 1/64 ≈ 1.5625%
```

| M (score) | gold % `=(2/256)·M` | `q(M)` | `1/q` |
|---|---|---|---|
| 2.0 (score 0) | 1.5625% | **0.0156250** | 64.00 |
| 2.5 (~tie) | 1.9531% | **0.0156250** | 64.00 |
| 5.0 | 3.9062% | **0.0156250** | 64.00 |
| 6.0 (max) | 4.6875% | **0.0156250** | 64.00 |

**`q` is exactly `1/64` for every M.** The boosted color distribution is multiplied by a *flat* `1/8` winning-color weight, so the boost factors out — the foil's rare-tail concentration is invisible to the match channel (robust at every off-grid `multBps`).

### G.2 — Match-tier probabilities per ticket-draw, `k ~ Binomial(4, q=1/64)`

| tier | formula | probability |
|---|---|---|
| P(2-of-4) | `C(4,2)·q²·(1−q)²` | 0.00141943 |
| P(3-of-4) | `C(4,3)·q³·(1−q)` | 0.00001502 |
| P(4-of-4) | `q⁴` | 5.960e-08 |

Identical at M = 2.0 / 2.5 / 5.0 / 6.0 (q is M-invariant).

### G.3 — Expected faces per pack over 30 days (V2: confirmed)

Payout table LOCKED (D-05): 2-of-4 = 5 faces, 3-of-4 = 65 faces, 4-of-4 = half whale pass (`whalePassClaims += 1`) + bonus spin (non-face, EV-negligible — G.6). Eligibility = 4 tickets × 2 draws/day × 30 days = **240 ticket-draws/pack**.

```
E[faces/draw]     = 5·P(2of4) + 65·P(3of4) = 5·0.00141943 + 65·0.00001502 = 0.0080736
E[faces/pack/30d] = 240 · 0.0080736 = 1.937628
```

| M (score) | E[faces/draw] | **E[faces/pack/30d]** | 2-of-4 share | 3-of-4 share |
|---|---|---|---|---|
| 2.0 / 2.5 / 5.0 / 6.0 | 0.008074 | **1.9376** | 87.91% | 12.09% |

**Realized = 1.94 faces/pack/30d, flat across all scores** — lands on the D-05 ~2-face target (3.1% low). Tier split **87.9% / 12.1%** (V2 note: vs the spec's illustrative ~85% / ~12%; build-time comment should cite 87.9%). **Not materially off; no recalibration flag.**

### G.4 — CRITICAL design intelligence: M-dependence of E[faces]

**E[faces] is completely flat in M — the two channels are fully decoupled.** The hypothesized gold-hunt-vs-match tension **does not materialize**: the winning color is *uniform*, not common-heavy, so the ticket's color distribution integrates to 1 against a flat `1/8` and the boost cancels. **V2 confirmed the mechanism** by counterfactual — a heavy-tail winning color WOULD make q vary (0.02382 @ M=2 vs 0.01479 @ M=6), proving the flatness is a genuine consequence of the uniform target, not a coincidence. Consequences:
- **Gold-hunt channel (§1):** strictly improving in M — `p_gold = (2/256)·M` rises 1.56% → 4.69% (×3) from score 0 to max.
- **Match channel (§3):** **independent of M** — locked at ~1.94 faces/pack.
- **No cross-channel tension.** A high activity score buys a better gold hunt *for free*, zero penalty to match faces. The ~2-face anchor holds at **every** score — no "calibrate-at-which-score" decision. Steer-proof: match faces cannot be gamed via activity score.

**LIVE hero-steering bound (V2-reproduced; upper bound, top wagerer only):** if the steerer's ticket hero-quadrant symbol equals the steered `heroSymbol`, that one quadrant's symbol-match becomes a point mass (`q_hero = 1/8`, color still uniform `1/8`), raising tier probs to P(2-of-4)=0.006309, P(3-of-4)=9.35e-5 and lifting E[faces/draw] on that draw from 0.00807 to **0.03762 (~4.66×)**. Bounded to a single quadrant on the at-most-one steerer/day and to the 2-of-4 / 3-of-4 tiers; the 4-of-4 whale-pass tier is gated HERO-FREE, so steering tops out at 3-of-4 — exactly §4 policy.

### G.5 — Gold-odds vs 10 tickets: crossover (V2: confirmed)

Depends only on `p_gold = (2/256)·M` over 16 boosted quadrants vs 40 baseline. Baseline `P(≥1 gold) = 1−(1−2/256)^40 = 26.9282%`.

| M (score) | `1−(1−p_gold)^16` | baseline (40 q) | verdict |
|---|---|---|---|
| 2.0 (score 0) | **22.2735%** | 26.9282% | worse at bottom ✓ (spec ≈22.3%) |
| **2.4854 (crossover)** | **26.9282%** | 26.9282% | exact tie (multBps ≈ 24,854) |
| 2.5 | 27.0643% | 26.9282% | ~tie ✓ |
| 5.0 | 47.1406% | 26.9282% | ahead |
| 6.0 (max) | **53.6128%** | 26.9282% | ~2× ✓ (spec ≈53.6%) |

**Crossover at M ≈ 2.4854** — the foil pack ties 10 normal tickets on gold odds at roughly score ~30–50 on the `foilBoostBps` curve (matches the spec's illustrative ~×2.5 tie). All three spec anchors reproduce exactly; independent of the taper weights `w_6…w_3`.

### G.6 — 4-of-4 (HERO-FREE) frequency (V2: confirmed)

4-of-4 gated HERO-FREE pure-VRF, so `q_heroFree = 1/64` on all four quadrants:
```
P(4-of-4 | single draw) = q⁴ = (1/64)⁴ = 5.960e-08   →  1-in-16,777,216
P(≥1 over a pack)       = 1 − (1 − q⁴)^240 = 1.43e-5  →  ~1-in-69,906 per pack
```
Per-pack ~1-in-69,906 is rarer than the spec's illustrative ≈1-in-300k context (the spec folds a narrower per-level window — documentation footnote, not a calibration error). Either way EV-negligible (~0.0014% per pack) and steer-proof (HERO-FREE gate).

**Calibration verdict:** payout table sound. Realized ~1.94 faces/pack/30d (D-05 ~2 target met, score-invariant). Match channel M-independent and fully decoupled from gold-hunt; gold crossover M≈2.485; 4-of-4 EV-negligible and steer-proof. No anchor materially off — **no recalibration required.**

---

## Canonical references

- **Locked design (wins on conflict):** `/home/zak/Dev/PurgeGame/degenerus-audit/.planning/V71-FOILPACK-FINAL-SPEC.md` (payout table §32-34,46; manipulation policy §4; storage §5)
- **Requirements (23 REQ-IDs):** `/home/zak/Dev/PurgeGame/degenerus-audit/.planning/REQUIREMENTS.md`
- **Discuss-phase decisions (D-01..D-05):** `/home/zak/Dev/PurgeGame/degenerus-audit/.planning/phases/445-spec-design-lock-the-implementation-contract/445-CONTEXT.md`

Key contract file:line anchors (re-verified at this baseline):

| Anchor | Path:line | Role |
|---|---|---|
| `weightedColorBucket` | `contracts/DegenerusTraitUtils.sol:115-126` | baseline color widths 64/64/64/32/16/8/6/2 (gold 2/256); frozen — DO NOT edit |
| `traitFromWord` | `contracts/DegenerusTraitUtils.sol:143` | frozen producer |
| `packedTraitsFromSeed` | `contracts/DegenerusTraitUtils.sol:169-177` | frozen 4-quadrant pack `[QQ][CCC][SSS]` |
| `packedTraitsDegenerette` / `_degTrait` | `contracts/DegenerusTraitUtils.sol:201-223` | SIBLING template for `packedTraitsFoil` / `traitFromWordFoil` |
| `ActivityCurveLib` knees / `decMultBps` / `centuryBps` | `contracts/libraries/ActivityCurveLib.sol:26, :29, :42-61, :74-90` | `foilBoostBps` idiom; SEG_B_KNEE=500, EFFECTIVE_CAP=30000 |
| `getRandomTraits` | `contracts/libraries/JackpotBucketLib.sol:281-286` | uniform winning-trait producer |
| `_applyHeroResult` | `contracts/modules/DegenerusGameJackpotModule.sol:1316-1341` | single-quadrant hero override (LIVE vs HERO-FREE) |
| `_rollWinningTraits` / `_rollWinningTraitsPair` | `contracts/modules/DegenerusGameJackpotModule.sol:1760-1795` | main+bonus roll; shared hero symbol |
| hero `dailyIdx == day-1` | `contracts/modules/DegenerusGameJackpotModule.sol:1290-1291` | claim must read `dailyHeroWagers[day-1]` |
| `cachedScore` / `_playerActivityScore` | `contracts/modules/DegenerusGameMintModule.sol:1709`; `DegenerusGameMintStreakUtils.sol:267` | buy-time score freeze source |
| `_processMintPayment` / `_recordMintPayment` | `contracts/modules/DegenerusGameMintModule.sol:236-299, :201-217` | payment + pool-split shape (afking leg rejected; 75/25 fork) |
| ETH-cap clone | `contracts/modules/DegenerusGameDegeneretteModule.sol:877-915` (`maxEth` :889, lootbox :915), `ETH_WIN_CAP_BPS` :221 | SEC-02 capped-spin path |
| `level` (raw) | `contracts/storage/DegenerusGameStorage.sol:236` | `uint24 public level`; cap keyed on raw level |
| century stamp idiom | `contracts/storage/DegenerusGameStorage.sol:1857-1876` | `foilRecord` stamp/auto-reset template |
| `whalePassClaims` (EXISTS) | `contracts/storage/DegenerusGameStorage.sol:1122` | 4-of-4 `+= 1`; do NOT re-declare |
| `rngWordByDay` | `contracts/storage/DegenerusGameStorage.sol:462` | retained daily VRF (claim re-derivation) |
| `dailyHeroWagers` | `contracts/storage/DegenerusGameStorage.sol:1841` | retained hero wager pool |
| `TICKET_SCALE` | `contracts/storage/DegenerusGameStorage.sol:157, :663` | 100 → 4 tickets = `quantityScaled = 400` |
| storage append point | `contracts/storage/DegenerusGameStorage.sol:2393` (`boxPlayers`), `}` at :2394 | tail append for `foilRecord` + `foilMatchClaimed` |
| `GAME_*_MODULE` constants | `contracts/ContractAddresses.sol:13-35` | add `GAME_FOILPACK_MODULE` |
| facade dispatch template | `contracts/DegenerusGame.sol:614-629` (`buyPresaleBox`) | thin stub pattern |
| `foundry.toml` build config | `via_ir`, `optimizer_runs=1000`, `evm_version=osaka`, `solc 0.8.34` | EIP-170 measurement basis |

---

## Appendix — raw verification verdicts (V1/V2/V3)

### V1 — PMF + curve

Independent exact-rational re-derivation (`fractions.Fraction`) + exhaustive integer-floor curve replication. **PMF: PASS** — mass Σ=1, all tiers ≥0, `p_gold = baseline×M` exact, taper monotone-decreasing, commons 0/1/2 sole funding sink, `/15360` ladder exact and non-negative at every `multBps ∈ [20000,60000]` (40,001 grid points, 0 mismatches/0 negatives), gold = `120·M`. PMF valid on `[2,6]`; true negativity-binding M = **8.8689** (well beyond 6). **Curve: PASS** — all 9 checks (×2 floor / ×6 ceiling, monotone over `[0,30001]`, saturation flat at ×6 from 30000, knees reused with one in-band seg-A knee at 300, "~×5 @ 350" honored by shape without pinning 350, `foilBoostBps(50)=25000`, value table + closed forms exact). **Discrepancies: none material.** One **wording-only** flag — Section A's "binding case M = 6" should read "worst case within the locked `[2,6]` range" (actual zero-crossing 8.8689; arithmetic/conclusion already correct). (Scripts: `/tmp/verify_foil.py`, `/tmp/verify_curve.py`.)

### V2 — calibration

**VERDICT: PASS.** Independent recompute (PMF rebuilt from baseline widths; `q(M)` re-derived from the uniform winning color; binomial / E[faces] / crossover redone). No discrepancy > 5% relative; every figure matches to full displayed precision; no correction required. Confirmed: `q=1/64` at all M (mechanism = uniform winning color cancels the boost — verified via heavy-tail counterfactual where q WOULD vary 0.02382→0.01479); E[faces]/pack/30d = **1.937628 ≈ 1.94** (D-05 ~2 target, 3.1% low, no flag); E[faces] completely flat in M; gold crossover M ≈ **2.48537** (multBps ≈ 24,854); all gold anchors (22.27% / ~tie / 53.61%) reproduce; 4-of-4 per-pack ~1-in-69,906; LIVE hero-steer draw E[faces]=0.03762 (~4.66×), bounded to 2/3-of-4, 4-of-4 steer-proof. Minor reporting notes (non-blocking, no number changed): tier split is **87.9% / 12.1%** (vs illustrative ~85%/~12%); 4-of-4 per-pack rarer than the illustrative ≈1-in-300k (narrower spec window). Source grounding re-verified (`DegenerusTraitUtils.sol:115-126`, `JackpotBucketLib.sol:281-286`, `DegenerusGameJackpotModule.sol:1316-1341`, spec §32-34,46).

### V3 — storage / signatures / placement

Adversarial re-read of D/E/F against source. **Verdict: all load-bearing claims PASS; 4 IMPL-precision defects (none alter the locked design); 0 layout/security/EIP-170 failures.**
- **Storage (D): PASS** — append point is the true tail (`boxPlayers:2393`, `}`:2394); century stamp idiom faithful; per-level auto-reset + persist-per-level griefing-resistance sound; cap folded into `foilRecord` (no desync); claimed-marker key collision-free (5 distinct `abi.encode` fields); append-only/no-slot-move (SEC-04). **DEFECT D-α (substantive, RECONCILED ABOVE):** D.1 (24-bit sigs, no `multBps`) vs E.6 (32-bit sigs + 16-bit `multBps`, 168 bits) disagree — **adopt the E.6 168-bit superset** (carries the frozen `multBps` required by RARE-03/MATCH-09).
- **Signatures/match (E): PASS** — LIVE/HERO-FREE split byte-faithful to `_rollWinningTraits`/`_rollWinningTraitsPair`; 4-of-4 steer-proof (gated on `heroFreeCount`); hero entropy reconstructed correctly (**IMPL anchor: read `dailyHeroWagers[day-1]`**, `:1290-1291`); double-claim marker 1:1 (CEI); entropy lanes disjoint (distinct keccak domains); payout isolated from Degenerette `quickPlay`; ETH ≤ 10% (`ETH_WIN_CAP_BPS=1000`). **DEFECT E-α (CORRECTED ABOVE):** `_queueTicketsScaled` quantity must be **`400`** (= 4 × `TICKET_SCALE 100`), not `4`. **DEFECT E-γ:** unify marker name → **`foilMatchClaimed`**.
- **Placement/EIP-170 (F): PASS** — all 12 measured sizes exact to the byte; build config as stated; MintModule correctly excluded; new `GAME_FOILPACK_MODULE` fits with ~13.5–16.5 KB headroom, facade ~3.3–3.7 KB. **DEFECT F-α (CORRECTED):** facade has **65 functions / 72 delegatecall sites**, not "48" (conclusion unaffected). **DEFECT F-β (CORRECTED):** ETH-cap clone source is `DegenerusGameDegeneretteModule.sol:877-915`, not `:402-446`. **F.4 note (CORRECTED):** `whalePassClaims` ALREADY exists (`:1122`) — do NOT add.
- **Net:** none of the defects invalidates the locked design or any HARD-REQ §6 floor; all corrected numbers are canonical above.