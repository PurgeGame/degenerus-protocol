# VERIFY — WWXRP Reel Rig + Payout Fork (Degenerette)

**Subject:** `contracts/modules/DegenerusGameDegeneretteModule.sol`
**Commit:** `1dd07c4d feat(degenerette): WWXRP reel rig + payout-fork recalibration`
**Baseline (v70 freeze):** `ffbd7796`
**Diff:** `git diff ffbd7796 HEAD -- contracts/modules/DegenerusGameDegeneretteModule.sol` (273 insertions on the module)
**Method:** code read (file:line) + independent re-derivation of the rigged distribution and EV in Python (NOT importing the canonical generator) + 2M-sample exhaustive simulation of the exact contract bit-logic + value-only byte-diff of constants + cross-module caller/RNG-freeze verification.
**Verdict:** all requirements MATCH. 0 CAT / 0 HIGH / 0 MED / 0 LOW. 3 INFO observations.

---

## Per-requirement verdict table

| Req | Statement | Verdict | Evidence |
|-----|-----------|---------|----------|
| RIG-01a | WWXRP-only rig; M≤6 (≥2 unmatched) → 60% flip exactly ONE unmatched ORDINARY cell | **MATCH** | `_rigWwxrpResult` L1299-1359: `if (m >= 7) return` (L1326), `if (rigSeed % 5 >= 3) return` (L1328 = 3/5 fire), single-cell forced + `return` (one flip). Sim: ΔS=+1 always when fired. |
| RIG-01b | A hero cell is NEVER flipped | **MATCH** | Pass-1 counts `u` only for `q != heroQuadrant` symbol (L1316); Pass-2 only forces symbol when `q != heroQuadrant` (L1345). Sim 2M: hero-flipped = 0. |
| RIG-01c | P(S=9) is PRESERVED (rig must not inflate apex/jackpot) | **MATCH** | Cap at M≥7 means a 1-off (M=7) or full (M=8) reel is never created or destroyed; S=9 (the all-7-ordinary + hero, M=8 event) is untouched. Independent calc: P(S9)_rig == P(S9)_honest to full Fraction precision for every N. Sim: rig-created-S9 = 0. |
| RIG-01d | Rig applies ONLY to WWXRP, never ETH/FLIP | **MATCH** | `_rigWwxrpResult` invoked at exactly 2 sites: L738 (guarded `if (currency == CURRENCY_WWXRP)`) and L1482 (`resolveWwxrpSpinFromBox`). `resolveFlipSpinsFromBox`/`resolveEthSpinFromBox` use the raw draw + `_score` directly. |
| RIG-02a | WWXRP resolves on its OWN rigged per-N tables, EV=100 per table | **MATCH** | `_getBasePayoutBps(N,s,isWwxrp=true)` dispatches `QUICK_PLAY_PAYOUTS_RIG_N{N}_PACKED` / `_RIG_N{N}_S8` (L1185-1207). Independent EV under rigged dist = 99.99652–99.99987 centi-x (≤100, within 0.5). |
| RIG-02b | flat 70% floor; RTP ladder {70,115,118,120}%; surplus → 6+ | **MATCH** | `WWXRP_FLOOR_BPS = 7000` flat for every WWXRP roll (L696-698, L1469); `_wwxrpRoi` piecewise {7000,11500,11800,12000} bps at score {0,305,500,30000}; surplus `roi−floor` redistributed via rigged factors into buckets B=6..9. Independent realized RTP = exactly {70,115,118,120}% per N. |
| RIG-02c | ETH & FLIP payout paths BYTE-IDENTICAL to pre-rig | **MATCH** | Honest `QUICK_PLAY_PAYOUTS_N*`, `_N*_S8/_S9`, `WWXRP_FACTORS_N*` byte-identical at `ffbd7796` vs HEAD (value-diff empty). ETH/FLIP take `isWwxrp=false` → honest tables; no rig call on those paths. Diff to ETH/FLIP funcs is only the additive `customTicket` selector (no payout-math change). |
| RIG-04 | Rig forces a REAL match (no phantom win); reads only frozen-at-commitment RNG | **MATCH** | Forced cell is set to the player's own color/symbol bits (L1338-1342, L1349-1353); sim: phantom (forced cell not actually matching) = 0. RNG: `rigSeed = hash2(resultSeed, WWXRP_RIG_SALT)`, `resultSeed = keccak(rngWord,index,[spinIdx],SALT)`, `rngWord = lootboxRngWordByIndex[index]` (frozen VRF). |
| PILLAR-RNG | Flip target + 60% gate from committed RNG; not steerable/grindable | **MATCH** | Commit gate `if (lootboxRngWordByIndex[index] != 0) revert` (L571) — bet committed BEFORE the word exists. Resolve gate `if (rngWord == 0) revert RngNotReady()` (L691). No caller-supplied data at resolve time mixes into the seed. Box path seed = `hash2(rngWord, player)` then `hash2(seed, BOX_WWXRP_SPIN_TAG)` — all frozen VRF; player addr is only a domain separator. |
| PILLAR-SOLV | WWXRP mint-backed; EV=100 holds arithmetically; no rounding overpay | **MATCH** | WWXRP paid via `wwxrp.mintPrize` (L486, L25) — mint-backed leg. Independent EV ≤ 100 centi-x for all 5 tables; generator enforces `ev_frac <= 100` (neutral-or-just-under) with a `payouts[6] -= 1` nudge. Byte-reproduce stat gate (`DegenerettePerNEvExactness.test.js`) re-asserts in CI. |

---

## EV arithmetic — INDEPENDENTLY computed (not via the generator)

I re-derived the variant-B rigged distribution `P_N^rig(S)` from first principles
(color axes: gold 1/15, common 2/15; 3 non-hero symbols 1/8; hero 1/8; convolution;
M≤6 → +1 ordinary cell w.p. 3/5), decoded the contract's packed RIG constants, and
summed `Σ payout(s)·P_N^rig(s)`.

### Per-N base table EV (rigged distribution)

| N | EV (centi-x) | ≤ 100? | drift from 100 |
|---|-------------:|:------:|---------------:|
| 0 | 99.99652 | yes | −0.348 centi-x |
| 1 | 99.99987 | yes | −0.013 |
| 2 | 99.99911 | yes | −0.089 |
| 3 | 99.99928 | yes | −0.072 |
| 4 | 99.99893 | yes | −0.107 |

All five tables are **neutral-or-just-under 100** — the base table is never EV-positive
for the house's counterparty in a way that overpays; max overshoot is 0 (all ≤ 100),
worst undershoot 0.348 centi-x (= 3.5 bps), well inside the design's ±0.5 centi-x band.
**No table overpays.** Matches the contract comment EVs (99.9965/99.9999/99.9991/99.9993/99.9989).

### P(S=9) invariance (rig must not inflate the apex)

| N | P(S9) rigged | P(S9) honest | identical? |
|---|-------------:|-------------:|:----------:|
| 0 | 7.716e-08 | 7.716e-08 | yes (exact Fraction) |
| 1 | 3.858e-08 | 3.858e-08 | yes |
| 2 | 1.929e-08 | 1.929e-08 | yes |
| 3 | 9.645e-09 | 9.645e-09 | yes |
| 4 | 4.823e-09 | 4.823e-09 | yes |

S=9 probability is **byte-identical** between rigged and honest distributions for every
N (exact rational equality, not just float-close). The apex/jackpot symbol odds are
preserved; the S=9 payout pin is shared (honest `QUICK_PLAY_PAYOUT_N{N}_S9`, dispatched
ahead of the rig branch at L1173-1180). Rig shapes only mid EV (S=2..8).

### RTP ladder (realized total RTP after floor + surplus redistribution)

Computed as `Σ P_N^rig(s)·payout(s)·effRoi(s)` with `effRoi = floor + (roi−floor)·factor/SCALE`
for s∈6..9, floor=7000 bps elsewhere:

| score | E(bps) target | N=0 | N=1 | N=2 | N=3 | N=4 |
|------:|--------------:|----:|----:|----:|----:|----:|
| 0 | 7000 | 70.00% | 70.00% | 70.00% | 70.00% | 70.00% |
| 305 | 11500 | 115.00% | 115.00% | 115.00% | 115.00% | 115.00% |
| 500 | 11800 | 118.00% | 118.00% | 118.00% | 118.00% | 118.00% |
| 30000 | 12000 | 120.00% | 120.00% | 120.00% | 120.00% | 120.00% |

The realized RTP hits the {70, 115, 118, 120}% ladder **exactly** for every N — the
rigged 10/30/30/30 factor family reconstitutes the total RTP precisely because the base
EV is pinned to ~100 and the factors are calibrated as `split·100·SCALE/(P(B)·payout(B))`.
`min _wwxrpRoi` over [0,30000] = 7000 bps = the flat floor → the floor never binds above
the curve (surplus = roi−floor is ≥ 0 everywhere, zero at score 0).

### Bonus-EV (per the generator's own assertions, re-confirmed)

Rigged bonus EV = exactly 5.00000% for all N (the surplus-redistribution machinery is
EV-conserving at the 500-bps reference; the contract scales this by the live surplus).

---

## Exhaustive bit-logic simulation (2,000,000 random samples of the EXACT contract logic)

Reimplemented `_rigWwxrpResult` bit-for-bit and ran it over uniformly random
`(playerTicket, resultTicket, heroQuadrant, rigSeed)` across the full 0..0xFFFFFFFF
trait space:

| Invariant | Violations |
|-----------|:----------:|
| Hero cell flipped | **0** |
| Fired with M ≥ 7 (should be capped) | **0** |
| Score change ≠ +1 when fired | **0** |
| Phantom win (forced cell not actually matching player) | **0** |
| Rig created S=9 | **0** |
| Fire-rate among M≤6 | **59.965%** (target 60.000%) |

Plus an exhaustive enumeration of all 256 match-patterns proving **u ≥ 1 whenever M ≤ 6**
→ the `(rigSeed >> 8) % u` pick never divides by zero (no revert path).

---

## Byte-reproduce / constant integrity

- All 15 RIG constants (5 `QUICK_PLAY_PAYOUTS_RIG_N{N}_PACKED` + 5 `QUICK_PLAY_PAYOUT_RIG_N{N}_S8`
  + 5 `WWXRP_FACTORS_RIG_N{N}_PACKED`) are **value-byte-identical** between the canonical
  generator (`.planning/notes/degenerette-recalibration/derive_5_tables.py`) stdout and the
  contract source.
- CI gate `test/stat/DegenerettePerNEvExactness.test.js` (HERO-04 PASS_ALL) spawns the
  generator, asserts exit 0, parses + byte-diffs all 15 rigged constants, replicates the
  rigged dispatch, and re-asserts P(S=9) invariance + rigged-dist neutrality. Honest
  (ETH/FLIP) constants byte-identical at `ffbd7796` vs HEAD.

## Cross-module wiring

- `resolveWwxrpSpinFromBox` / `resolveFlipSpinsFromBox` / `resolveEthSpinFromBox` each gained
  a 5th `uint32 customTicket` param. Interface (`IDegenerusGameModules.sol:450+`) and both
  callers — `DegenerusGameFoilPackModule.sol:628` and `DegenerusGameLootboxModule.sol:2094/2112/2132`
  — pass all 5 args in correct order (`uint32(0)` for the seed-derived case). No 4-arg ABI mismatch.
- The WWXRP box emits the **post-rig** `resultTicket` in `BoxSpin` (rig at L1482 overwrites
  before `_packSpin` at L1515) → display reel == scored reel (honest display).

---

## Ranked issues

**None at CAT/HIGH/MED/LOW.** Three INFO observations (no action required):

### INFO-1 — Base table EV undershoots 100 by up to 0.35 centi-x (by design)
N=0 rigged table EV = 99.99652 (−3.5 bps). This is the generator's deliberate
"neutral-or-just-under" guarantee (`while total_ev > 100: payouts[6] -= 1`), so the base
table is never EV-positive for the player before the activity-ROI/bonus scaling. The
realized RTP ladder still lands exactly on {70,115,118,120}% because the surplus factors
are calibrated against the actual (rounded) per-N payouts and probabilities, absorbing the
sub-centi-x base drift. Suggested action: none — this is the intended slack direction
(house-safe).

### INFO-2 — `WWXRP_FLOOR_BPS` and `WWXRP_ROI_MIN_BPS` are both 7000 (intentional coupling)
The flat floor equals the curve minimum, so surplus redistribution is exactly 0 at score 0
and the floor never binds above the curve. Confirmed `min _wwxrpRoi = 7000` over the full
score domain. If a future change lowers `WWXRP_ROI_MIN_BPS` below the floor, the surplus
`roi − floor` would go negative and the `if (...wwxrpHighRoi > roiBps)` guard at L1148 would
zero the bonus (no underflow — the subtraction is guarded). Suggested action: keep the two
constants documented as coupled (they already are, L218-225).

### INFO-3 — `resolveWwxrpSpinFromBox` reuses the box `seed` for both the result draw and the rig seed
`heroQuadrant = uint8(seed & MASK_2)`, the player ticket (when `customTicket==0`), the result
draw (`hash2(seed,1)`), and the rig (`hash2(seed, WWXRP_RIG_SALT)`) all derive from the same
`seed`. This is correct and non-steerable (seed is frozen VRF-derived `hash2(rngWord, player)`),
and the distinct salts (`1` vs `WWXRP_RIG_SALT`) domain-separate the draws so the rig entropy
is independent of the result reel. Suggested action: none — noted only because the shared base
is worth being aware of for any future seed-reuse review; no correlation defect found.

---

## Conclusion

The as-built rig and payout fork match the locked design on every requirement. EV=100 (≤100,
neutral-or-just-under) holds arithmetically for all 5 rigged tables; the RTP ladder lands
exactly on {70,115,118,120}%; P(S=9) is preserved to exact rational precision; the rig never
flips a hero cell, never fires above M=6, forces only real matches, and reads only frozen VRF
entropy; ETH/FLIP payout paths are byte-identical to the v70 freeze. No solvency drift, no
steerability, no apex inflation, no off-by-one in the M≤6 gate.
