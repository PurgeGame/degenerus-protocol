# Degenerus Protocol — v70.0 Audit Findings

**Milestone:** v70.0 — Activity-Score Consumer-Curve & Bucket Reshape (Verify + Re-Audit)
**Date:** 2026-06-19
**Subject (frozen):** `contracts/` tree **`99f2e53f`** (FREEZE commit **`ffbd7796`**). Baseline was the v69.0 closure subject `contracts/` tree **`8a633d1d`** (HEAD `3f024cc8`). The tree advanced only via the single batched, USER-approved reshape commit recorded below.
**Closure signal:** MILESTONE_V70_AT_HEAD___CLOSURE_SHA__
**Method:** The reshape was already written in the working tree at milestone start; the milestone = VERIFY → FREEZE → TST → REAUDIT → TERMINAL (not design→build). VERIFY (440) used a Claude adversarial verification workflow — 8 independent per-dimension verifiers recomputing every curve/ladder/inverse from the locked design with Solidity integer arithmetic, a completeness critic, and per-gap adversarial confirmation — plus empirical build/sizes and the targeted oracle suites. FREEZE (441) is the sole approval gate: one batched `contracts/*.sol` diff, USER hand-reviewed and approved. Honest admin/governance assumed; pre-launch, no live funds.
**Regression floor:** final full forge suite **935 passed / 0 failed / 108 skipped** (134 suites; the 108 skips are pre-existing `vm.skip`) on the frozen tree.

---

## Verdict: 0 CATASTROPHE / 0 HIGH / 0 MED / 0 LOW · 0 open findings on the final subject

v70 is a **read-side reward-curve reshape**: it changes the *consumer mappings* of the (whole-point, v69) player activity score so the high end is reserved for long quest streaks — a steep early ramp, a near-flat long tail, and the previous MAX now reached only at score 30,000. **MIN and MAX of every curve are byte-identical to before the reshape; no payout changes at the extremes — only the ramp shape.** The shared multiplier + bucket-ladder math is centralized in a new pure library (`ActivityCurveLib`) so the FLIP and decimator paths cannot drift and the century bonus is identical between the mint and afking paths. The reshape was **byte-frozen and adversarially verified**; every value curve, the bucket ladder, the exact inverse, the pre-clamp removal, and the full consumer migration match the locked design. **The named risk — the v69 incomplete-migration failure class — was swept clean.** Nets are green; **0 findings remain open.**

| Phase | Category | Verdict |
|---|---|---|
| 440 VERIFY | Adversarial review of the working tree vs the locked design | OK 8/8 dimensions MATCH; 0 confirmed defects; 1 cosmetic comment fix applied in-tree |
| 441 FREEZE | Batched 7-file `.sol` diff (the sole approval gate) | OK atomic USER-approved commit `ffbd7796`; subject byte-frozen at tree `99f2e53f`; no edits outside the consumer-curve surface |
| 442 TST | Prove curves / ladder / inverse / reachable-tail / century-parity | OK 17/17 targeted green; oracle rewritten OLD→new formulas; century Mint↔Afking parity added |
| 443 REAUDIT | Re-run the v68/v69 detection nets on the reset subject | OK layout unmoved · RNG-freeze re-attested · suite 935/0/108 + 18 invariant suites green; mutation/Halmos carried |
| 444 TERMINAL | Evidence pack + closure | OK this document |

---

## The reshape — what changed (and what did not)

Five value curves and two bucket curves share one 3-segment piecewise shape: `vA = MIN + 90%·(MAX−MIN)` at the old cap K, `vB = MIN + 98%` at the seg-B knee (500), `MAX` at the effective cap (30,000), flat beyond. The six per-site `235/305` pre-clamps were **removed** (the curves self-saturate; the raw score is already bounded by the `65,534` hard cap), so the high end is now reachable. The score **computation** and the affiliate taper are **out of scope and untouched**.

| Consumer curve | Site | K | MIN → MAX | Endpoints byte-identical? |
|---|---|---|---|---|
| Decimator / terminal multiplier | `ActivityCurveLib.decMultBps` (FLIP + Decimator) | 235 | 1.000× → 1.7833× | yes (MAX = old `10000+235·100/3`) |
| Degenerette ROI | `_roiBpsFromScore` (Degenerette) | 305 | 90.00% → 99.90% (strictly <100%) | yes |
| WWXRP high ROI | `_wwxrpHighValueRoi` (Degenerette) | 305 | 90.00% → 109.90% | yes |
| Century bonus | `ActivityCurveLib.centuryBps` (Mint + Afking) | 305 | 0% → 100% of qty | yes |
| Lootbox EV | `_lootboxEvMultiplierFromScore` (Storage) | 400 | 90% → 145% (neutral 100% @60 kept) | yes |

**Bucket ladder** (`decBucket`): absolute thresholds `12@0, 11@10, 10@30, 9@55, 8@85, 7@120, 6@180, 5@250, 4@300, 3@500, 2@1000`, clamped up to each path's floor (normal 5; century/terminal 2). **Exact inverse** (`minScoreForBucket`): the band-floor `2→1000 … 12→0`, sealing the decimator-claim lootbox-EV score.

---

## VERIFY (440) — adversarial verification, 0 defects

The 8-dimension workflow + completeness critic independently confirmed, against the locked design:

- **Value curves** — every waypoint exact under truncating integer arithmetic; monotonic non-decreasing over the full hard-cap domain; continuous at every knee; MAX byte-identical to the old saturated max; the decimator `s==0 → 1.0×` no-op preserved and honored downstream by the `multBps <= BPS_DENOMINATOR` short-circuit. **Solvency:** Degenerette ROI strictly < 10000 globally (max 9990); lootbox EV ≤ 14500 still gated by `LOOTBOX_EV_BENEFIT_CAP`; century ≤ 100% still ETH-capped (20-ETH `maxBonus` at both sites); multiplier ≤ 17833.
- **Bucket ladder + inverse + wiring** — all 11 thresholds correct; `minScoreForBucket` round-trips exactly through the forward ladder for every bucket 2..12; FLIP and Decimator both delegate to the single lib with the old local bodies deleted (no drift).
- **Pre-clamp removal + full consumer migration** — all six pre-clamps gone; `git grep` finds zero residual old saturated arithmetic, zero orphaned/stale constants (`ACTIVITY_SCORE_MID_POINTS`, `ACTIVITY_SCORE_HIGH_POINTS`, `ROI_MID_BPS`, `ROI_HIGH_BPS` removed). The completeness critic cleared **4 additional `_lootboxEvMultiplierFromScore` call sites** (Lootbox:566, Mint:1785, Whale:893, Afking:1018) that the first sweep under-counted — all route through the reshaped function with the benefit cap intact. **The v69 incomplete-migration failure class is swept clean.**
- **Build + bounds** — `forge build` clean; `ActivityCurveLib` storageless (57-byte inlined stub); EIP-170 satisfied (DegenerusGame 20,388 / 4,188 headroom = the v69 baseline, Game did not grow; FLIP 7,668 / 16,908); no read-side gas regression (straight-line branch ladders, no loops/SLOADs in the hot paths); `advanceGame` 16.7M ceiling not implicated (no curve runs in the advance loop).

### V70-INFO-01 — cosmetic — two stale NatSpec comments (FIXED in-tree, in the FREEZE diff)
`DegenerusGameDecimatorModule.sol` (:157, :627) named the deleted `FLIP._adjustDecimatorBucket` helper. Re-pointed to `ActivityCurveLib.decBucket`. Comment-only; no bytecode change. This is the only orchestrator edit on top of the original reshape, and it is part of the single approved FREEZE commit.

---

## FREEZE (441) — the sole approval gate

ONE batched `contracts/*.sol` commit **`ffbd7796`** (`feat(v70): activity-score consumer-curve & bucket reshape`): the new `ActivityCurveLib.sol` + the six modified contracts (FLIP, Decimator, Degenerette, Mint, Afking, Storage). USER hand-reviewed the diff and approved it. The diff was confirmed (per-hunk) to contain **no edits outside the activity-score consumer-curve surface** — no storage-layout change, no signature change, no logic touched beyond the reshape and the V70-INFO-01 comment fix. New v70 subject byte-frozen at `contracts/` tree **`99f2e53f`**.

---

## TST (442) — 17/17 targeted green (test-only)

The three consumer-curve oracle files were rewritten from the OLD formulas to the new 3-segment curves, with a century parity test added:
- **Value-curve endpoints + shape** — golden waypoints for all five curves at 12 anchors each (multiplier + century assert directly against `ActivityCurveLib`; ROI/WWXRP/lootbox against byte-faithful mirrors, the module bodies being `private`); MIN/MAX exact + cap byte-identity; dense monotonicity; continuity at every knee; ROI strictly sub-100%; the `s==0` no-op pinned.
- **Bucket ladder + inverse** — every threshold crossing + just-below edges; floor-5 (normal) / floor-2 (century/terminal) paths; exact `minScoreForBucket` round-trip.
- **Reachable tail + century parity** — `decBucket(1000,2)=2` and each curve reaches MAX exactly at 30,000 (the pre-clamp-removal fix), and the new `test_CenturyBonus_MintAfkingParity` proves the Mint and Afking century bonuses are identical for identical inputs (one shared helper). The V69 migration suite correctly **dropped its 4 old-shape oracle tests** that asserted the pre-reshape curves.

---

## REAUDIT (443) — nets green on the reset subject

- **Storage-layout golden (REAUDIT-01):** `storage_layout_oracle.sh --check` → **all 24 goldens match**, delegatecall shared-slot consistency OK. **Zero slot movement** — the expected result for a read-side reshape with a storageless lib; the slot-pinned harnesses remain valid.
- **RNG-freeze proof (REAUDIT-02):** all freeze/determinism suites green (`RngFreezeAndRemovalProofs` 15, `RngLockDeterminism` 22, `V55FreezeDeterminism` 7, `PrizePoolFreeze` 9, `DegeneretteFreezeResolution` 10, `V61RngFreezeIntact` 6, + the freeze/VRF-path invariant suites). Every activity-score RNG/VRF consumer is re-attested frozen-at-commitment: the reshape changes only the pure formula applied to the already-frozen score (lootbox EV reads the frozen `LB_SCORE`; Degenerette ROI/WWXRP read the frozen packed bet score; the decimator re-derives the sealed score via the exact `minScoreForBucket` inverse). No new live re-read inside any RNG window; no freeze-proof anchor moved.
- **Regression + invariant (REAUDIT-03):** full forge suite **935 / 0 / 108** + 18 invariant suites green (solvency, freeze-window, VRF-path, composition, redemption, degenerette, whale-sybil). EIP-170 re-confirmed.

---

## Carried recommendations (non-blocking)

1. **Mutation + Halmos symbolic on the reshaped surface** — the formal gambit campaign and a Halmos pass on `ActivityCurveLib` remain the milestone long-pole (each mutant = a via_ir recompile; CI/detached), consistent with the v63/v64/v67/v68/v69 closes. Triage: the changed surface is pure integer arithmetic with near-complete concrete oracle coverage (every waypoint pinned, knees continuous, monotonic dense-scanned, inverse round-tripped), so the expected kill-rate on the changed surface is high; the carry is the formal campaign, not a behavior gap.
2. **Direct module-body test coverage for ROI / WWXRP** — currently byte-faithful local mirrors (the module bodies are `private`). A future integration test through the public Degenerette bet-settlement path would assert against the live bodies directly.
3. **Indexer / off-chain re-vendor** — by design (locked-design §7), the VALUES carried by `DecimatorBurn.bucketUsed`, `DecBurnRecorded.{bucket,effectiveAmount}`, `TerminalDec*.bucket`, `BetPlaced`→settled ROI/WWXRP, `FullTicketResolved` payouts, and `LootBoxOpened.{futureTickets,flip}` shift; no signature or storage change. Indexer reconstruction tables must be re-vendored.

Visual reference: `ACTIVITY-SCORE-CONSUMER-CURVES.html` (the five value curves, the normalized shared-shape overlay, and the bucket ladder + inverse, rendered from the exact on-chain formulas).

---

## Closure

The reshape is correct against the locked design, builds and stays within bounds, proves out under the rewritten oracle, and passes every re-run detection net with zero unexpected drift. Subject byte-frozen at the FREEZE diff `ffbd7796` (`contracts/` tree `99f2e53f`) — the only `contracts/*.sol` change of the milestone. **0 open findings.** UNPUSHED (push is the USER's call).
