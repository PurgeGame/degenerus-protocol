# ✅ CLOSED 2026-07-09 — SHIPPED in frozen tree d5e9f58a (LOOTBOX_LARGE_FLIP_LOW_BASE_BPS=4_388, STEP=360 verified live at LootboxModule:301/303). Original spec below.
# shift 1/3 of lootbox FLIP EV into tickets via variance ladder

Branch chances (%20 roll) and `LOOTBOX_TICKET_ROLL_BPS` (19,678) UNCHANGED. Two constant
groups move in `contracts/modules/DegenerusGameLootboxModule.sol`. Blocked until the v75
mutation campaign completes (same reason as pending-comment-fixes-post-mutation.md).
Derivation: session scratchpad `variance_ladder_solve.py` (exact Fraction enumeration of
the solidity integer interpolation).

## 1. FLIP ladder (REVISED v2): total FLIP EV × 2/3 AND 20% of the spins-branch equity
##    moved into the flat branch (flat weight 0.15→0.17, spins 0.10→0.08 of main;
##    flat:spins split 60:40 → 68:32). Implementation: ladder carries the flat branch
##    (= original × 34/45); the spins branch gets a stake-haircut constant (× ~12/17).
- LOOTBOX_LARGE_FLIP_LOW_BASE_BPS   5_808  ->  4_388
- LOOTBOX_LARGE_FLIP_LOW_STEP_BPS     477  ->    360
- LOOTBOX_LARGE_FLIP_HIGH_BASE_BPS 30_705  -> 23_199
- LOOTBOX_LARGE_FLIP_HIGH_STEP_BPS  9_430  ->  7_125
- NEW: LOOTBOX_FLIP_SPINS_STAKE_BPS = 7_060 — in `_resolveLootboxRoll` roll 17-18:
  `stake = (_largeFlipOut(amount, targetPrice, seed) * LOOTBOX_FLIP_SPINS_STAKE_BPS) / 10_000`
New ranges: low 43.88%–97.88% (was 58.08%–129.63%), high 231.99%–445.74% (was 307.05%–589.95%).
New E[largeFlip] = 1.24477x (was 1.64784x); spins conditional stake 0.8788x (0.2929x per spin ×3).
Flat EV 0.186716 / spins EV 0.087881×roi per unit main; total-FLIP residual vs the ×2/3
target = −4.6e-5 (−0.005% of box EV, ladder rounding). Foil-pack FLIP spins unaffected
(stake = faces × FLIP_FACE_AMOUNT, not ladder-derived).
(Superseded v1: plain ladder × 2/3 = 3_872/318/20_470/6_287 with no stake split.)

## 2. Ticket variance tiers (chances 1/4/20/45/30% unchanged; delivers the 0.13732 EV/main;
##    also scales the roll-19 ETH-spin stake, preserving its EV-equal-to-tickets invariant)
- TIER1: 32_000–60_000 -> 40_000–65_000   (4.00–6.50x, mean 5.25x; 6.50x is the uint16
  ceiling — pure scaling wanted ~7.18x; widen the constant type if a bigger top is desired)
- TIER2: 16_000–30_000 -> 20_000–35_000   (2.00–3.50x, mean 2.75x)
- TIER3:  8_000–14_000 -> 10_000–16_000   (1.00–1.60x, mean 1.30x — tier 3 never below face)
- TIER4:  4_510– 8_510 ->  5_923– 9_923   (0.5923–0.9923x, mean ~0.792x; solver tier, width
  4_000 kept)
- TIER5:  3_000– 6_000 ->  3_600– 7_200   (0.36–0.72x, mean 0.54x)
New E[variance] = 0.940985 (was 0.785900). Ticket-branch conditional face 1.5465x -> 1.8517x.

## Result (per unit of post-boon roll amount, FLIP at face)
- ticketEV 0.6959 -> 0.8333 ; flipEV 0.4120 -> 0.2746 ; split 62.8:37.2 -> 75.2:24.8
- within FLIP: flat 0.1867 (68%) + spins 0.0879×roi (32%)  [was 60:40]
- total-EV residual +0.000012 tickets (E_VAR drift) − 4.6e-5 FLIP (ladder rounding)

## Diff must also update adjacent comments to the new values (describe what IS, no history):
- per-tier "(4.6x/2.3x/1.1x/0.651x mean)" and inline "// 3.20x"-style band comments
- the tier block comment's "overall variance EV (~0.786x)" -> ~0.941x (drop the
  "unchanged vs prior static value" framing)
- FLIP ladder comments "(58.1%)" etc. and `_largeFlipOut`'s "58%-130% / 307%-590%" ranges
- Degenerette/lootbox docs quoting the old means where applicable

## Test impact to check at implementation time (post-campaign):
- grep tests/stat oracles for hardcoded 5808/477/30705/9430/8510/4510/3000/6000/32000 and
  any asserted ~0.786x variance EV or ~1.648x FLIP EV; update oracles alongside.
- knock-ons (intentional): box FLIP emission (creditFlip faucet) −33% on every box path;
  box-sourced ticket issuance +19.7% (entry dilution at target levels rises accordingly);
  roll-19 ETH-spin stakes +19.7%.
