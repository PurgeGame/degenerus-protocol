---
phase: 327-tst-repro-same-results-no-arb-ev-regression-proofs
plan: 04
subsystem: degenerette-hero-rescale
tags: [HERO, TST, byte-reproduce, DGAS, no-leak, stat-gate, foundry]
requires:
  - "326-03 applied diff (S=A+2H scoring, S8/S9 separate-uint256 dispatch, WWXRP B=6..9, DGNRS S>=7)"
  - "derive_5_tables.py (extended canonical generator)"
provides:
  - "Canonical 10-bucket S∈{0..9} EV-equal payout generator (byte-reproduce source of truth)"
  - "PASS_ALL byte-reproduce gate (regenerate-from-script, never hand-typed)"
  - "Foundry scoring/packing/threshold + DGAS write-batch + dailyHeroWagers no-leak proofs"
  - "Ready-to-apply FINAL contract constants (S0..7 packed + S8 + WWXRP) for the contract-constant landing"
affects:
  - "327-06 full-suite regression gate (owns the cross-phase closure of the RED byte-reproduce gate)"
  - "HERO-04 contract-constant landing (out of this TST phase; needs the hand-review CONTRACTS_COMMIT_APPROVED gate)"
tech-stack:
  added: []
  patterns:
    - "spawnSync python3 generator + parse FINAL PASTE-READY hex + diff vs contract source (Phase-267-style PASS_ALL)"
    - "score read off FullTicketResult.matches (the S=A+2H field) via the public resolve path (_score is private)"
    - "snapshot batched-vs-per-bet differential for DGAS byte-identity"
    - "identical-wagers / different-scores differential for the daily-hero no-leak"
key-files:
  created:
    - "test/fuzz/DegeneretteHeroScore.t.sol"
  modified:
    - ".planning/notes/degenerette-recalibration/derive_5_tables.py"
    - "test/stat/DegenerettePerNEvExactness.test.js"
    - "test/stat/DegeneretteBonusEv.test.js"
decisions:
  - "Payout SHAPE over S∈{2..8} = [190,475,1500,4250,19500,100000,5_000_000] (frequent-small/juicy-top carried from the 9-bucket design; near-jackpot S=8 tier below S=9), S=9 PINNED to the M=8 relabel"
  - "S=9 == old M=8 event/odds (relabel; values unchanged); S=8 + S=9 separate uint256s per the FROZEN contract dispatch; S=0..7 packed 32-bit"
  - "WWXRP factor buckets B=6..9 (shift-by-one), packed 64-bit with B=6 low; ETH bonus EV = 5.000% per N at 10/30/30/30"
  - "byte-reproduce gate stays RED-with-recorded-diff against the Phase-326 placeholders (15/20 diverge; 5 S9 match) — the EXPECTED in-scope no-contract-phase outcome; gate NOT weakened"
metrics:
  duration: "~1 session"
  tasks: 3
  files: 4
  completed: 2026-05-26
---

# Phase 327 Plan 04: HERO Byte-Reproduce + DGAS + No-Leak Proofs Summary

The Degenerette hero 2-point rescale (S = A + 2*H, max 9, pay floor S>=2) is proven byte-reproducible from the canonical generator and write-batch / daily-hero-jackpot safe against the applied Phase-326 diff — with the contract-constant landing surfaced as an explicit STOP/handoff.

## What was built

### Task 1 — Canonical 10-bucket generator + PASS_ALL byte-reproduce gate (commit `39a706ca`)
- **`derive_5_tables.py` EXTENDED** to the S∈{0..9} design: P_N(S) = convolution over 4 color axes (gold 1/15, common 2/15) + 3 non-hero symbol axes (Bernoulli 1/8) + 1 hero symbol axis (Bernoulli 1/8 contributing 0 or 2). The standalone HERO_BOOST/HERO_PENALTY/HERO_SCALE derivation is DELETED. The script asserts `sum_S P_N(S) == 1`, S=9 reproduces the old M=8 scaling (relabel consistency), per-N basePayoutEV drift `< 0.5` centi-x, and ETH bonus EV `== 5.000%`. It exits 0 (assertions are hard).
- **Chosen payout SHAPE** (documented inline): S∈{2..8} = `[190, 475, 1500, 4250, 19500, 100000, 5_000_000]` (relative; scaled per-N to EV=100 with residual-absorption refine on S=4/5/6), S=9 PINNED to the M=8 relabel constants. Per-N basePayoutEV: 100.00028 / 99.99976 / 99.99998 / 99.99985 / 99.99999 (|max drift| = 0.0278 bps = 0.00028 centi-x).
- **PASS_ALL gate** (`DegenerettePerNEvExactness.test.js`, full rewrite): spawnSync python3 (status === 0 asserted BEFORE parse — T-327-04-FC5), parse the FINAL PASTE-READY hex (NEVER hand-typed — T-327-04-FC1), read the contract source, diff each of the 20 constants. The gate is NOT weakened to pass against placeholders (T-327-04-FC2). Per-N EV exactness uses the REGENERATED tables.
- **`DegeneretteBonusEv.test.js`** (full rewrite): WWXRP/ETH-bonus re-bucketing to B=6..9 on the regenerated factors; ETH bonus EV == 5.000% ± 1% per N (measured drift `< 0.001%`).

### Task 2 — Foundry scoring / packing / thresholds (commit `c8e1fcf5`)
`test/fuzz/DegeneretteHeroScore.t.sol` — 4 tests, all GREEN against the applied diff regardless of placeholder VALUES (they assert scoring SHAPE / dispatch / behavior, read the contract's score off `FullTicketResult.matches`):
- `test_HERO_ScoreFormula`: S = A + 2*H capped at 9; hero-alone (A=0,H=1) ⇒ S=2 win; hero quadrant COLOR is an ordinary axis (contributes 1, not 2).
- `test_HERO_S9EqualsOldM8Jackpot`: self-match ⇒ S=9 pays the FINAL `QUICK_PLAY_PAYOUT_N{N}_S9` relabel constant per N (isolated via BURNIE; roiBps decoded from the stored activityScore).
- `test_HERO_S8S9PackingDecodable`: S=9→separate nonzero S9; S=8→separate S8 slot (placeholder 0 shows through the FINAL dispatch shape); S=0..7→packed slot decode.
- `test_HERO_DgnrsThresholdsRemapped`: award gate fires only S>=7 (S=6 none) with BPS S=7→4% / S=8→8% / S=9→15%, measured via the Reward-pool delta (isolates the gate award from the lootbox-path DGNRS reward).

### Task 3 — HERO-06 DGAS + no-leak (commit `d4ec2e62`)
Same file, 2 tests:
- `test_HERO06_WriteBatchByteIdentical_DGAS`: a mixed-currency batch (ETH 4 spins + BURNIE 3 + WWXRP 2, same ticket) resolved in ONE `resolveBets` vs the SAME bets one-at-a-time (snapshot, identical VRF) is byte-identical in claimable, claimablePool, BURNIE/WWXRP mint deltas, and the per-spin FullTicketResult stream (keccak digest).
- `test_HERO06_DailyHeroJackpotUnaffected_NoLeak`: two runs with IDENTICAL wagers but DIFFERENT resolution scores produce the IDENTICAL 32-slot `dailyHeroWagers` ledger (via `getDailyHeroWager`) and the IDENTICAL `getDailyHeroWinner`; resolution never mutates the wager ledger. Non-vacuity: the two runs DO score differently (S mirror) and the ledger is non-empty.

## Results

| Proof | Result |
|-------|--------|
| Generator exit code | 0 (all asserts pass) |
| Per-N basePayoutEV (regenerated tables) | 100 ± 0.0003 centi-x, all 5 N GREEN |
| ETH bonus EV (regenerated B=6..9 factors) | 5.000% ± <0.001%, all 5 N GREEN |
| PASS_ALL byte-reproduce gate | **RED-with-diff (EXPECTED)** — 15/20 placeholders diverge; 5 S9 relabel MATCH |
| Foundry scoring/packing/thresholds (Task 2) | 4/4 GREEN |
| Foundry DGAS + no-leak (Task 3) | 2/2 GREEN |
| `contracts/*.sol` (mainnet) edits | 0 |

Stat-suite chain (`DegenerettePerNEvExactness` + `DegeneretteBonusEv`): **15 passing / 1 failing** (the 1 failure = the byte-reproduce gate's expected RED).

Foundry (`DegeneretteHeroScore.t.sol`): **6 passing / 0 failing**.

## STOP — HERO BYTE-REPRODUCE NEEDS CONTRACT-CONSTANT LANDING

The byte-reproduced finals must live in `contracts/modules/DegenerusGameDegeneretteModule.sol`, which currently ships the INTENTIONAL Phase-326 placeholders (committed `f50cc634`). Replacing them is a `contracts/*.sol` MAINNET EDIT — HARD-PROHIBITED in this TST phase. The PASS_ALL gate therefore REMAINS RED against the placeholders. **This RED-with-recorded-diff is the EXPECTED, in-scope no-contract-phase outcome — NOT a plan failure.** The finals are produced by the authoritative generator (never hand-typed) and are ready to apply under the hand-review `CONTRACTS_COMMIT_APPROVED=1` gate. Cross-phase closure of this RED gate is owned by **327-06** (the full-suite regression gate, which documents the expected post-landing failure-count delta).

### Placeholder → FINAL diff (15/20 constants diverge; 5 S9 MATCH)

| Family | Constant | Placeholder (contract now) | FINAL (generator) | State |
|--------|----------|----------------------------|-------------------|-------|
| packed | `QUICK_PLAY_PAYOUTS_N0_PACKED` | `0x0001a42c…000000cc00000000` | `0x0000ccf1…0000006400000000` | REPLACE |
| packed | `QUICK_PLAY_PAYOUTS_N1_PACKED` | `0x0001eb86…000000ef00000000` | `0x0000f45d…0000007700000000` | REPLACE |
| packed | `QUICK_PLAY_PAYOUTS_N2_PACKED` | `0x000241d9…0000011900000000` | `0x00012085…0000008c00000000` | REPLACE |
| packed | `QUICK_PLAY_PAYOUTS_N3_PACKED` | `0x0002ac13…0000014d00000000` | `0x0001523e…000000a500000000` | REPLACE |
| packed | `QUICK_PLAY_PAYOUTS_N4_PACKED` | `0x0003310c…0000018d00000000` | `0x00018aa1…000000c000000000` | REPLACE |
| S8 | `QUICK_PLAY_PAYOUT_N0_S8` | `0` | `2623243` | REPLACE |
| S8 | `QUICK_PLAY_PAYOUT_N1_S8` | `0` | `3127840` | REPLACE |
| S8 | `QUICK_PLAY_PAYOUT_N2_S8` | `0` | `3693049` | REPLACE |
| S8 | `QUICK_PLAY_PAYOUT_N3_S8` | `0` | `4329524` | REPLACE |
| S8 | `QUICK_PLAY_PAYOUT_N4_S8` | `0` | `5051269` | REPLACE |
| WWXRP | `WWXRP_FACTORS_N0_PACKED` | `0x…03fd603d…00ddba9f…001923d6` | `0x…00301e47…00769797…0011b417` | REPLACE |
| WWXRP | `WWXRP_FACTORS_N1_PACKED` | `0x…05fd43a6…01285f24…001e36c9` | `0x…00459aab…0096dc93…0014250d` | REPLACE |
| WWXRP | `WWXRP_FACTORS_N2_PACKED` | `0x…0914e5e4…0192745c…0024f43d` | `0x…0067a3f9…00c6a960…0017af89` | REPLACE |
| WWXRP | `WWXRP_FACTORS_N3_PACKED` | `0x…0dd6ad96…0228fcb0…002de0ce` | `0x…009dba9b…010d8a6d…001cbc40` | REPLACE |
| WWXRP | `WWXRP_FACTORS_N4_PACKED` | `0x…151a90e7…02fdeaff…00399efe` | `0x…00f40c44…0176ef73…0023de94` | REPLACE |
| S9 | `QUICK_PLAY_PAYOUT_N{0..4}_S9` | `10756411 / 12583037 / 14792939 / 17512324 / 20916435` | identical | **MATCH (final)** |

### Ready-to-apply FINAL constants (regenerate to confirm: `python3 .planning/notes/degenerette-recalibration/derive_5_tables.py`)

```solidity
uint256 private constant QUICK_PLAY_PAYOUTS_N0_PACKED = 0x0000ccf1000027f9000008b700000311000000f9000000640000000000000000;
uint256 private constant QUICK_PLAY_PAYOUTS_N1_PACKED = 0x0000f45d00002fa800000a61000003aa00000129000000770000000000000000;
uint256 private constant QUICK_PLAY_PAYOUTS_N2_PACKED = 0x000120850000384600000c44000004560000015f0000008c0000000000000000;
uint256 private constant QUICK_PLAY_PAYOUTS_N3_PACKED = 0x0001523e000041f500000e5d000005100000019b000000a50000000000000000;
uint256 private constant QUICK_PLAY_PAYOUTS_N4_PACKED = 0x00018aa100004cf0000010c8000005ea000001e0000000c00000000000000000;

uint256 private constant QUICK_PLAY_PAYOUT_N0_S8 = 2623243;
uint256 private constant QUICK_PLAY_PAYOUT_N1_S8 = 3127840;
uint256 private constant QUICK_PLAY_PAYOUT_N2_S8 = 3693049;
uint256 private constant QUICK_PLAY_PAYOUT_N3_S8 = 4329524;
uint256 private constant QUICK_PLAY_PAYOUT_N4_S8 = 5051269;

// S9 already FINAL in the contract (unchanged relabel) — re-stated for completeness:
uint256 private constant QUICK_PLAY_PAYOUT_N0_S9 = 10756411;
uint256 private constant QUICK_PLAY_PAYOUT_N1_S9 = 12583037;
uint256 private constant QUICK_PLAY_PAYOUT_N2_S9 = 14792939;
uint256 private constant QUICK_PLAY_PAYOUT_N3_S9 = 17512324;
uint256 private constant QUICK_PLAY_PAYOUT_N4_S9 = 20916435;

uint256 private constant WWXRP_FACTORS_N0_PACKED = 0x0000000002278add0000000000301e470000000000769797000000000011b417;
uint256 private constant WWXRP_FACTORS_N1_PACKED = 0x0000000003aef46a0000000000459aab000000000096dc93000000000014250d;
uint256 private constant WWXRP_FACTORS_N2_PACKED = 0x0000000006442ce7000000000067a3f90000000000c6a960000000000017af89;
uint256 private constant WWXRP_FACTORS_N3_PACKED = 0x000000000a96251f00000000009dba9b00000000010d8a6d00000000001cbc40;
uint256 private constant WWXRP_FACTORS_N4_PACKED = 0x0000000011ba25db0000000000f40c44000000000176ef73000000000023de94;
```

After the landing, the PASS_ALL gate flips to 0-diff GREEN and the `DegeneretteHeroScore.t.sol` `test_HERO_S8S9PackingDecodable` S=8 sub-case will pay nonzero (the placeholder-0 expectation in that sub-case is the one assertion keyed to the pre-landing state — 327-06 documents this expected delta).

## DGAS batched-vs-per-bet result
Byte-identical: claimable delta, claimablePool delta, BURNIE mint delta, WWXRP mint delta, and the per-spin `FullTicketResult` stream (keccak digest) all match between the single `resolveBets` call and the same bets resolved one-at-a-time. Non-vacuity confirmed (all three currencies exercised nonzero).

## No-leak differential result
Two runs with IDENTICAL wagers but DIFFERENT resolution scores produced the IDENTICAL 32-slot `dailyHeroWagers` ledger and the IDENTICAL `getDailyHeroWinner` (quadrant/symbol/amount). Resolution never mutated the wager ledger (pre == post in both runs). Non-vacuity: the two runs scored differently (mirrored `_score`), and the wager ledger was non-empty. The 0-8 → 0-9 matches-range change cannot leak into the daily-hero jackpot.

## Deviations from Plan
None — plan executed exactly as written. The RED byte-reproduce gate + STOP handoff is the planned, in-scope outcome of the no-contract phase (the plan's CRITICAL SCOPE NOTE + `<HERO_04_EXPECTED_OUTCOME>`), not a deviation.

## Known Stubs
The contract holds the Phase-326 INTENTIONAL placeholders (15/20 constants). They are NOT this plan's stubs — they are the documented cross-phase handoff (see `## STOP` above; resolved by the contract-constant landing + 327-06). No new stubs introduced by this plan's test/generator authoring.

## Notes on the harness
- The stat-gate hardhat run emits a cosmetic `Cannot find module 'test/stat/…'` at teardown (a known Hardhat+mocha ESM file-unloader quirk that fires AFTER the verdict is reported); it does not affect the 15-passing/1-failing result.
- The out-of-scope `test/stat/DegeneretteProducerChi2.test.js` (in the `test:stat` script but NOT in this plan's files) still references the OLD `_countMatches`/`_applyHeroMultiplier` dispatch — any breakage there from the Phase-326 diff is out-of-scope for this plan and owned by the 327-06 full-suite regression gate.

## Self-Check: PASSED
- Created/modified files all FOUND: `test/fuzz/DegeneretteHeroScore.t.sol`, `.planning/notes/degenerette-recalibration/derive_5_tables.py`, `test/stat/DegenerettePerNEvExactness.test.js`, `test/stat/DegeneretteBonusEv.test.js`, `327-04-SUMMARY.md`.
- Per-task commits all FOUND: `39a706ca` (Task 1), `c8e1fcf5` (Task 2), `d4ec2e62` (Task 3).
