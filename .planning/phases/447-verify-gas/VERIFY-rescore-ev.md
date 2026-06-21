# VERIFY — Foil MATCH "Variant-2" rescore (RIG-03 / MATCH-10)

**Subject:** commit `16225de6` — *graded "Variant-2" match scoring + EV-neutral payout table*
**Baseline:** v70.0 freeze `ffbd7796` (subject tree `99f2e53f`)
**Scope:** the foil MATCH grader + face-table EV in `contracts/modules/DegenerusGameFoilPackModule.sol`. READ-ONLY review.
**Date:** 2026-06-21

---

## 1. Verdict table

| Check | Design (locked) | As-built (file:line) | Result |
|---|---|---|---|
| Grader = Variant-2 color-gated-by-symbol | symbol +1 always; +1 more iff symbol matched; symbol miss = 0; T∈{0..8} | `_tryClaimFoilMatch` `:493-500`: `if (sym==sym) score += (col==col)?2:1` | **PASS** |
| Pay gate | pay only T ≥ 4; {0..3} revert | `:501` `if (score < 4) return false;` | **PASS** |
| Face table | {4→2, 5→6, 6→35, 7→400, 8→10000} | `:65-69` `FOIL_FACES_T4..T8 = 2,6,35,400,10000`; dispatch `:508-518` | **PASS — exact** |
| ½ whale pass moonshot | at T=8 (= old 4-of-4) | `:583` `if (tier == 8) whalePassClaims[player] += 1;` | **PASS** |
| E[faces/comparison] | 0.010972 | recomputed **0.01097178** | **PASS (ratio 0.99999 vs prior)** |
| E[faces/pack/30d] | 2.6333 | recomputed **2.63323** | **PASS (err 0.001%)** |
| Per-ticket match EV ~flat in score | ≈1.95 fresh → 2.16 max (f=P) | recomputed **1.9486 → 2.1571** | **PASS** |
| P(T=k) ladder | T4 1/310, T5 1/2761, T6 1/32388, T7 1/599186, T8 1/16.78M | recomputed **identical to last digit** | **PASS** |
| Currency split untouched (MATCH-06) | 40/40/20 ETH/FLIP/WWXRP off `c%100`, tier-independent | `:592-635` unchanged; dispatch keyed on `c`, not `score`/`tier` | **PASS** |
| Double-pay between graded face and currency spin | none | single `if/else if/else` currency lane; whale pass is additive-only at T=8 | **PASS — none** |
| Foil tests green | — | `FoilPackEV` 4/4 + `FoilLadderParity` 4/4 (1000-run fuzz) | **PASS** |

**Overall: the as-built rescore faithfully implements the locked design. Face table is an exact match; recomputed EV reproduces both 2.16/ticket and 2.63/pack to within rounding.**

---

## 2. Independent EV derivation

### 2.1 Per-quadrant contribution (boost-invariant)
Daily winning set is uniform 6 bits/quadrant → symbol match `ps = 1/8`, color match `pc = 1/8`,
both boost-invariant (`Σ_c P_foil(c)·(1/8)=1/8` for any boost). Per quadrant:

| contrib | meaning | prob |
|---|---|---|
| 0 | symbol miss (color irrelevant) | 1 − ps = **7/8** |
| 1 | symbol hit, color miss | ps·(1−pc) = **7/64** |
| 2 | symbol hit, color hit | ps·pc = **1/64** |

### 2.2 T = sum of 4 i.i.d. quadrant contributions (exact convolution)

| T | P(T) exact | P(T) | 1/x | face | EV-share |
|---|---|---|---|---|---|
| 0 | 2401/4096 | 5.862e-1 | 1/2 | — | — |
| 1 | 2401/8192 | 2.931e-1 | 1/3 | — | — |
| 2 | 12691/131072 | 9.682e-2 | 1/10 | — | — |
| 3 | 10633/524288 | 2.028e-2 | 1/49 | — | — |
| **4** | 54145/16777216 | 3.227e-3 | **1/310** | 2 | 58.8% |
| **5** | 1519/4194304 | 3.622e-4 | **1/2761** | 6 | 19.8% |
| **6** | 259/8388608 | 3.088e-5 | **1/32388** | 35 | 9.8% |
| **7** | 7/4194304 | 1.669e-6 | **1/599186** | 400 | 6.1% |
| **8** | 1/16777216 | 5.960e-8 | **1/16,777,216** | 10000 | 5.4% |

Σ P(T) = 1.000 (verified). Every 1/x matches the locked design memo exactly.

### 2.3 EV
- `E[faces/comparison] = Σ_{T≥4} P(T)·face(T) = 46019/4194304 = 0.0109718`
- Prior `liveCount` table (Binom(4,1/64), {2→7,3→65,4→1000}): `0.0109719` → **ratio 0.99999** (byte-identical, as the commit claims).
- `E[faces/pack/30d] = 240 · 0.0109718 = 2.63323` (240 = 4 tickets × 2 drawKinds × 30 days). Design = 2.6333; **err 0.001%.**

### 2.4 Realized per-ticket match EV (tickets)
`tickets/pack/30d = 2.6332 · [0.40·RTPeth + 0.40·(f/P)·RTPflip + 0.20·0]`, RTPeth=(roi+500)/1e4, RTPflip=roi/1e4:

| score | roiBps | f=P | f=0 |
|---|---|---|---|
| fresh ~0 | 9000 | **1.9486** | 1.0006 |
| max | 9990 | **2.1571** | 1.1049 |

→ reproduces design's ≈1.95→2.16 (f=P, ~flat, +10.7%) and ≈1.0→1.1 (f=0). **Confirmed.**

### 2.5 Frequency
- P(T≥4 / comparison) = 0.003622 (1 in 276 single-ticket comparisons).
- P(pack pays ≥1 / draw) = 0.01441 → 1/69.4 draws ≈ **0.865 paying draws/pack/30d** (~1 graded match per pack per ~35 days), matching the commit message's "~1/pack/~35d."

---

## 3. T=8 ⟺ old 4-of-4 (whale-pass relocation is event-identical)

T=8 requires each of the 4 quadrants to contribute 2 ⟺ symbol AND color match in every quadrant.
A full 6-bit `[CCC][SSS]` quadrant match (the old `liveCount` criterion) is precisely "symbol AND color
match." So **T=8 ⟺ all 4 quadrants full-match ⟺ old 4-of-4** (P = 5.96e-8 = 1/16,777,216, identical to the
old Binom(4,1/64) 4-of-4). Moving the ½-whale-pass grant from `tier==4` to `tier==8` (`:583`) fires on the
identical event. **Sound.**

---

## 4. Composition / double-pay / off-by-one checks

- **No double-pay.** `_payFoilTier` `:604-635` is a single `if (c<40) … else if (c<80) … else …` currency
  dispatch — exactly one lane pays per claim. The whale-pass at `:583-585` is an *additional* grant for T=8
  only; `whalePassClaims` is written in exactly one place in the whole module (grep-confirmed). No path pays
  both a graded face and a separate currency spin for the same claim.
- **Currency-spin tiers untouched (MATCH-06).** The 40/40/20 ETH/FLIP/WWXRP split keys on `c = keccak(...)%100`
  (`:592-594`), entirely independent of `score`/`tier`. The rescore did not touch the split, the stakes
  (`faces·priceForLevel` / `faces·FLIP_FACE_AMOUNT` / `faces·WWXRP_FACE_AMOUNT`), or `_foilSpin`. Diff confirms.
- **No grader off-by-one.** Loop adds {0,1,2}/quadrant; gate `score<4` excludes T∈{0,1,2,3}; dispatch
  `score==4/5/6/7/else` covers T∈{4..8} bijectively (`else`⟹8 since score∈[4,8] post-gate). T=4 is reachable
  by every composition (2+2, 2+1+1, 1+1+1+1) — the convolution already sums all of them, and P(T=4)=1/310
  matched the design. No boundary defect.
- **Event field.** `FoilMatchClaimed.tier` now carries T∈{4..8} (was {2,3,4}); the indexer doc comment was
  updated (`:99-102`). Indexer must be re-vendored to read the new domain (see INFO-1).

---

## 5. Ranked issues

### INFO-1 — Indexer `tier` field domain changed {2,3,4} → {4..8}
`FoilMatchClaimed.tier` semantics changed. Any off-chain indexer/analytics keyed on the old 2/3/4 tiers
will mis-bucket. The doc comment was updated and the field name retained intentionally, but the *value
domain* widened. **Suggested:** flag the indexer re-vendor in the 449 terminal carry list (no contract change).

### INFO-2 — Face-EV byte-identity is asserted only analytically, not by a unit test
`FoilLadderParity` pins the trait *producer* (boost ladder), and `FoilPackEV` is a coarse logging harness with
no hard EV assertion. The 0.99999 face-EV parity (this report §2.3) and the P(T) ladder are not pinned by any
forge test. **Suggested (test-only, no contract change):** add a pure-math forge assertion that
`Σ P(T)·FOIL_FACES_T{k}` over the exact convolution equals the prior `Binom(4,1/64)` table to ≤0.01%, so a
future face retune can't silently drift EV. This is the 447 TST / MATCH-10 empirical-confirm slot.

### INFO-3 — Residual EV under-shoot of 2.6333 target is 0.001% (cosmetic)
As-built E[faces/pack/30d] = 2.63323 vs target 2.6333 (the exact-arithmetic optimum given integer faces).
The faces are integers, so this is the closest integer table — not a defect, noted for completeness. The
2.0-vs-2.6333 wording in MATCH-10 vs RIG-03 is a documentation artifact: **the code implements the refined
2.6333 figure** (RIG-03), and MATCH-10's "≈2" is the rounded headline. No discrepancy in code.

**No CAT / HIGH / MED / LOW findings.** The rescore is a localized, EV-preserving, event-preserving swap.

---

## 6. Suggested fixes (do NOT apply)
- INFO-1: add indexer re-vendor to the 449 carry list (off-chain).
- INFO-2: add a pure forge math test pinning `Σ P(T)·face(T)` ≈ prior table (test-only) — fits the 447 TST slot.
- INFO-3: none required; the integer table is optimal.

---

## 7. Method notes
- EV recomputed independently from first principles (exact `fractions`-based convolution of the 4 i.i.d.
  quadrant contributions); not copied from the design memo. Every figure matched.
- `.planning/sims/foil_jackpot_ev_mc.py` ran green (EXIT 0) but covers the *jackpot/rarity* channel (component
  b), orthogonal to the match-box-spin face EV verified here — it corroborates the surrounding design, not RIG-03.
- `forge test --match-contract "FoilLadderParityTest|FoilPackEV"` → 8/8 PASS, compile clean.
