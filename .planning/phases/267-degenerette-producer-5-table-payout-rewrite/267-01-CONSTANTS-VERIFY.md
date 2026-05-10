# Phase 267 — Constants Verification

**Generated:** 2026-05-10
**Script:** `.planning/notes/degenerette-recalibration/derive_5_tables.py`
**Source-of-truth note:** `.planning/notes/2026-05-10-degenerette-payout-recalibration.md` §"CONSTANT REWRITE"
**Decision:** D-267-CONSTVERIFY-01 — Task 2 BLOCKS Task 3 on any mismatch.
**Verdict:** **PASS_ALL_25**

This artifact captures the reproducible re-derivation of all 25 packed constants
the Phase 267 contract diff will paste into `contracts/modules/DegenerusGameDegeneretteModule.sol`,
and proves byte-identity between the script's `Fraction`-exact stdout and the
planning-note pasted `.sol` hex strings. Phase 268 STAT-05 separately empirically
verifies on-chain dispatch produces `basePayoutEV = 100.00 ± 0.50 centi-x`.

---

## Re-run Provenance

```bash
python3 .planning/notes/degenerette-recalibration/derive_5_tables.py > /tmp/267-derive-stdout.txt 2>&1
echo "Exit: $?"        # → 0
wc -l /tmp/267-derive-stdout.txt   # → 144
```

Exit 0, 144 lines. Script ran cleanly with the locked color distribution
`[16,16,16,16,16,16,16,8]/120` (D-267-DIST-01), basePayoutEV target 100 centi-x
(D-267-EV-TARGET-01), M=4/M=5/M=6 cascade for residual absorption
(D-267-EV-PRECISION-01), 10/30/30/30 WWXRP split (D-267-WWXRP-SPLIT-01), and
symbol-only hero (D-267-HERO-01).

---

## Script stdout (verbatim)

```
  N |    E[M] |    M=0 P(M) |    M=1 P(M) |    M=2 P(M) |    M=3 P(M) |    M=4 P(M) |    M=5 P(M) |    M=6 P(M) |    M=7 P(M) |    M=8 P(M)
----------------------------------------------------------------------------------------------------------------------------------
  0 |  1.0333 |  0.3307049 |  0.3924849 |  0.2037503 |  0.0604297 |  0.0111995 |  0.0013281 |  0.0000984 |  0.0000042 |  0.0000001
  1 |  0.9667 |  0.3561437 |  0.3933235 |  0.1891032 |  0.0516584 |  0.0087620 |  0.0009438 |  0.0000630 |  0.0000024 |  0.0000000
  2 |  0.9000 |  0.3835394 |  0.3919688 |  0.1736024 |  0.0434705 |  0.0067219 |  0.0006563 |  0.0000394 |  0.0000013 |  0.0000000
  3 |  0.8333 |  0.4130424 |  0.3880783 |  0.1574035 |  0.0359525 |  0.0050517 |  0.0004466 |  0.0000242 |  0.0000007 |  0.0000000
  4 |  0.7667 |  0.4448149 |  0.3812699 |  0.1407068 |  0.0291788 |  0.0037168 |  0.0002977 |  0.0000147 |  0.0000004 |  0.0000000

5 EV-equal payout tables (shape preserved, scaled to basePayoutEV = 100 centi-x):

  M | multiplier |    N=0 payout |    N=1 payout |    N=2 payout |    N=3 payout |    N=4 payout
    |  (centi-x) |     centi-x   |     centi-x   |     centi-x   |     centi-x   |     centi-x  
----------------------------------------------------------------------------------------------------
  0 |          0 |             0 |             0 |             0 |             0 |             0
  1 |          0 |             0 |             0 |             0 |             0 |             0
  2 |        190 |           204 |           239 |           281 |           333 |           397
  3 |        475 |           511 |           598 |           703 |           832 |           994
  4 |      1,500 |         1,620 |         1,887 |         2,218 |         2,617 |         3,149
  5 |      4,250 |         4,570 |         5,351 |         6,292 |         7,447 |         8,894
  6 |     19,500 |        20,977 |        24,535 |        28,844 |        34,153 |        40,794
  7 |    100,000 |       107,564 |       125,830 |       147,929 |       175,123 |       209,164
  8 | 10,000,000 |    10,756,411 |    12,583,037 |    14,792,939 |    17,512,324 |    20,916,435

Scale factors (relative to N=0 baseline):
  N=0:  ×1.075641  → basePayoutEV = 100.0000 centi-x
  N=1:  ×1.258304  → basePayoutEV = 100.0000 centi-x
  N=2:  ×1.479294  → basePayoutEV = 100.0000 centi-x
  N=3:  ×1.751232  → basePayoutEV = 100.0000 centi-x
  N=4:  ×2.091643  → basePayoutEV = 100.0000 centi-x

Top-bucket multipliers per table (× the bet amount, at 100% ROI):
  N |        M=4 |        M=5 |        M=6 |        M=7 |     M=8 jackpot
  0 |     16.20x |     45.70x |    209.77x |   1075.64x |    107,564.11x
  1 |     18.87x |     53.51x |    245.35x |   1258.30x |    125,830.37x
  2 |     22.18x |     62.92x |    288.44x |   1479.29x |    147,929.39x
  3 |     26.17x |     74.47x |    341.53x |   1751.23x |    175,123.24x
  4 |     31.49x |     88.94x |    407.94x |   2091.64x |    209,164.35x

P(any payout, M >= 2) per table:
  N=0: 27.6810%   (1 in 3.6 tickets)
  N=1: 25.0533%   (1 in 4.0 tickets)
  N=2: 22.4492%   (1 in 4.5 tickets)
  N=3: 19.8879%   (1 in 5.0 tickets)
  N=4: 17.3915%   (1 in 5.7 tickets)

Constant-storage requirement:
  5 packed payout schedules: 5 × uint256 = 5 constants for M=0..7
  5 separate uint256 for M=8 jackpot (since values exceed 32 bits): 5 constants
  Total: 10 constants for the payout side

WWXRP_BONUS_FACTOR (per-N) preview at 10/30/30/30 split, ETH_BONUS_BPS=500:
  N |    BUCKET5 factor |    BUCKET6 factor |    BUCKET7 factor |    BUCKET8 factor
------------------------------------------------------------------------------------------
  0 |         1,647,574 |        14,531,231 |        66,936,893 |        36,145,885
  1 |         1,980,105 |        19,423,012 |       100,484,006 |        61,797,482
  2 |         2,421,821 |        26,375,260 |       152,364,516 |       105,131,239
  3 |         3,006,670 |        36,240,560 |       232,172,950 |       177,612,063
  4 |         3,776,254 |        50,195,199 |       354,062,567 |       297,412,059

  Total WWXRP factor constants: 5 × 4 = 20 (vs 4 in single-normalizer proposal)

Hero boost under SYMBOL-ONLY hero match (user simplification):
  P(hero symbol matches | M, N) — table indexed by (N, M):
  P_N still varies, but hero match is uniform 1/8 — no hero_type sub-tables.

  M |   N=0 P(h|M) → boost |   N=1 P(h|M) → boost |   N=2 P(h|M) → boost |   N=3 P(h|M) → boost |   N=4 P(h|M) → boost
--------------------------------------------------------------------------------------------------------------
  2 |       0.2421 → 11566 |       0.2587 → 11433 |       0.2775 → 11302 |       0.2987 → 11174 |       0.3226 → 11050
  3 |       0.3651 → 10870 |       0.3877 → 10790 |       0.4122 → 10713 |       0.4386 → 10640 |       0.4667 → 10571
  4 |       0.4894 → 10522 |       0.5157 → 10469 |       0.5430 → 10421 |       0.5707 → 10376 |       0.5981 → 10336
  5 |       0.6151 → 10313 |       0.6422 → 10279 |       0.6687 → 10248 |       0.6937 → 10221 |       0.7167 → 10198
  6 |       0.7421 → 10174 |       0.7662 → 10153 |       0.7877 → 10135 |       0.8064 → 10120 |       0.8226 → 10108
  7 |       0.8704 → 10074 |       0.8862 → 10064 |       0.8986 → 10056 |       0.9085 → 10050 |       0.9167 → 10045

  HERO_BOOST_PACKED per N (16 bits each, M=2 lowest):
    HERO_BOOST_PACKED_N0 = 0x275a27be2849291a2a762d2e
    HERO_BOOST_PACKED_N1 = 0x275027a9282728e52a262ca9
    HERO_BOOST_PACKED_N2 = 0x27482797280828b529d92c26
    HERO_BOOST_PACKED_N3 = 0x2742278827ed288829902ba6
    HERO_BOOST_PACKED_N4 = 0x273d277c27d62860294b2b2a

Hero-boost spread across N (do we need 5 tables, or is one enough?):
  M  | N=0    N=1    N=2    N=3    N=4    | spread (max-min)/avg
  2  | 11566  11433  11302  11174  11050   |  4.56%
  3  | 10870  10790  10713  10640  10571   |  2.79%
  4  | 10522  10469  10421  10376  10336   |  1.78%
  5  | 10313  10279  10248  10221  10198   |  1.12%
  6  | 10174  10153  10135  10120  10108   |  0.65%
  7  | 10074  10064  10056  10050  10045   |  0.29%

  → User chose FULL per-N design for <0.01% EV-equality across picks.

======================================================================
FINAL PASTE-READY CONSTANTS
======================================================================

// Payout tables (per-N): basePayoutEV = 100 centi-x ± rounding
uint256 private constant QUICK_PLAY_PAYOUTS_N0_PACKED   = 0x0001a42c000051f1000011da00000654000001ff000000cc0000000000000000;  // EV=100.0000
uint256 private constant QUICK_PLAY_PAYOUTS_N1_PACKED   = 0x0001eb8600005fd7000014e70000075f00000256000000ef0000000000000000;  // EV=100.0000
uint256 private constant QUICK_PLAY_PAYOUTS_N2_PACKED   = 0x000241d9000070ac00001894000008aa000002bf000001190000000000000000;  // EV=100.0000
uint256 private constant QUICK_PLAY_PAYOUTS_N3_PACKED   = 0x0002ac130000856900001d1700000a39000003400000014d0000000000000000;  // EV=100.0000
uint256 private constant QUICK_PLAY_PAYOUTS_N4_PACKED   = 0x0003310c00009f5a000022be00000c4d000003e20000018d0000000000000000;  // EV=100.0000

uint256 private constant QUICK_PLAY_PAYOUT_N0_M8       =    10756411;  // 107,564.11x bet
uint256 private constant QUICK_PLAY_PAYOUT_N1_M8       =    12583037;  // 125,830.37x bet
uint256 private constant QUICK_PLAY_PAYOUT_N2_M8       =    14792939;  // 147,929.39x bet
uint256 private constant QUICK_PLAY_PAYOUT_N3_M8       =    17512324;  // 175,123.24x bet
uint256 private constant QUICK_PLAY_PAYOUT_N4_M8       =    20916435;  // 209,164.35x bet

// Hero boost tables (per-N), symbol-only match: P(hero|M,N) × boost + (1-P) × penalty = scale
uint256 private constant HERO_BOOST_N0_PACKED          = 0x275a27be2849291a2a762d2e;
uint256 private constant HERO_BOOST_N1_PACKED          = 0x275027a9282728e52a262ca9;
uint256 private constant HERO_BOOST_N2_PACKED          = 0x27482797280828b529d92c26;
uint256 private constant HERO_BOOST_N3_PACKED          = 0x2742278827ed288829902ba6;
uint256 private constant HERO_BOOST_N4_PACKED          = 0x273d277c27d62860294b2b2a;

// WWXRP factors (per-N) at 10/30/30/30 split, basePayoutEV=100, ETH_BONUS_BPS=500
uint256 private constant WWXRP_FACTORS_N0_PACKED       = 0x0000000002278add0000000003fd603d0000000000ddba9f00000000001923d6;
uint256 private constant WWXRP_FACTORS_N1_PACKED       = 0x0000000003aef46a0000000005fd43a60000000001285f2400000000001e36c9;
uint256 private constant WWXRP_FACTORS_N2_PACKED       = 0x0000000006442ce7000000000914e5e4000000000192745c000000000024f43d;
uint256 private constant WWXRP_FACTORS_N3_PACKED       = 0x000000000a96251f000000000dd6ad96000000000228fcb000000000002de0ce;
uint256 private constant WWXRP_FACTORS_N4_PACKED       = 0x0000000011ba25db00000000151a90e70000000002fdeaff0000000000399efe;

// Per-pick EV verification (basePayoutEV centi-x):
//   N | basePayoutEV | drift from 100
//   0 |   99.99997   |  -0.00 bps
//   1 |  100.00002   |  +0.00 bps
//   2 |  100.00002   |  +0.00 bps
//   3 |  100.00001   |  +0.00 bps
//   4 |  100.00001   |  +0.00 bps

// ETH-bonus EV verification (target = 5.0000%):
//   N=0: bonus EV = 5.000000%   drift +0.0000 bps
//   N=1: bonus EV = 5.000000%   drift +0.0000 bps
//   N=2: bonus EV = 5.000000%   drift +0.0000 bps
//   N=3: bonus EV = 5.000000%   drift +0.0000 bps
//   N=4: bonus EV = 5.000000%   drift -0.0000 bps

// Total ETH player RTP @ MAX activity (9990 bps + 5% bonus):
//   N=0: total RTP = 104.9000%
//   N=1: total RTP = 104.9000%
//   N=2: total RTP = 104.9000%
//   N=3: total RTP = 104.9000%
//   N=4: total RTP = 104.9000%
```

---

## Byte-identity assertions (25 grep pairs)

For each constant, the script-emitted hex/decimal byte-string is grep-extracted from
`/tmp/267-derive-stdout.txt`, and compared verbatim against the planning-note
`.sol` pasted hex/decimal in `.planning/notes/2026-05-10-degenerette-payout-recalibration.md`
§"CONSTANT REWRITE". String comparison is exact; numeric values normalized for
underscore-separator differences (script: `10756411`; note: `10_756_411`).

### Family 1 — Per-N payouts (M=0..7 packed; 64 hex chars per uint256)

| Constant                       | Script hex                                                           | Planning-note hex                                                    | Verdict |
| ------------------------------ | -------------------------------------------------------------------- | -------------------------------------------------------------------- | ------- |
| `QUICK_PLAY_PAYOUTS_N0_PACKED` | `0x0001a42c000051f1000011da00000654000001ff000000cc0000000000000000` | `0x0001a42c000051f1000011da00000654000001ff000000cc0000000000000000` | PASS    |
| `QUICK_PLAY_PAYOUTS_N1_PACKED` | `0x0001eb8600005fd7000014e70000075f00000256000000ef0000000000000000` | `0x0001eb8600005fd7000014e70000075f00000256000000ef0000000000000000` | PASS    |
| `QUICK_PLAY_PAYOUTS_N2_PACKED` | `0x000241d9000070ac00001894000008aa000002bf000001190000000000000000` | `0x000241d9000070ac00001894000008aa000002bf000001190000000000000000` | PASS    |
| `QUICK_PLAY_PAYOUTS_N3_PACKED` | `0x0002ac130000856900001d1700000a39000003400000014d0000000000000000` | `0x0002ac130000856900001d1700000a39000003400000014d0000000000000000` | PASS    |
| `QUICK_PLAY_PAYOUTS_N4_PACKED` | `0x0003310c00009f5a000022be00000c4d000003e20000018d0000000000000000` | `0x0003310c00009f5a000022be00000c4d000003e20000018d0000000000000000` | PASS    |

### Family 2 — Per-N M=8 jackpot single value (decimal)

| Constant                  | Script value | Planning-note value | Verdict |
| ------------------------- | ------------ | ------------------- | ------- |
| `QUICK_PLAY_PAYOUT_N0_M8` | `10756411`   | `10_756_411`        | PASS    |
| `QUICK_PLAY_PAYOUT_N1_M8` | `12583037`   | `12_583_037`        | PASS    |
| `QUICK_PLAY_PAYOUT_N2_M8` | `14792939`   | `14_792_939`        | PASS    |
| `QUICK_PLAY_PAYOUT_N3_M8` | `17512324`   | `17_512_324`        | PASS    |
| `QUICK_PLAY_PAYOUT_N4_M8` | `20916435`   | `20_916_435`        | PASS    |

### Family 3 — Per-N hero boost (M=2..7 packed; 24 hex chars / 96 bits per uint256)

| Constant               | Script hex                     | Planning-note hex              | Verdict |
| ---------------------- | ------------------------------ | ------------------------------ | ------- |
| `HERO_BOOST_N0_PACKED` | `0x275a27be2849291a2a762d2e`   | `0x275a27be2849291a2a762d2e`   | PASS    |
| `HERO_BOOST_N1_PACKED` | `0x275027a9282728e52a262ca9`   | `0x275027a9282728e52a262ca9`   | PASS    |
| `HERO_BOOST_N2_PACKED` | `0x27482797280828b529d92c26`   | `0x27482797280828b529d92c26`   | PASS    |
| `HERO_BOOST_N3_PACKED` | `0x2742278827ed288829902ba6`   | `0x2742278827ed288829902ba6`   | PASS    |
| `HERO_BOOST_N4_PACKED` | `0x273d277c27d62860294b2b2a`   | `0x273d277c27d62860294b2b2a`   | PASS    |

### Family 4 — Per-N WWXRP factors (B=5..8 packed; 64 hex chars per uint256)

| Constant                  | Script hex                                                           | Planning-note hex                                                    | Verdict |
| ------------------------- | -------------------------------------------------------------------- | -------------------------------------------------------------------- | ------- |
| `WWXRP_FACTORS_N0_PACKED` | `0x0000000002278add0000000003fd603d0000000000ddba9f00000000001923d6` | `0x0000000002278add0000000003fd603d0000000000ddba9f00000000001923d6` | PASS    |
| `WWXRP_FACTORS_N1_PACKED` | `0x0000000003aef46a0000000005fd43a60000000001285f2400000000001e36c9` | `0x0000000003aef46a0000000005fd43a60000000001285f2400000000001e36c9` | PASS    |
| `WWXRP_FACTORS_N2_PACKED` | `0x0000000006442ce7000000000914e5e4000000000192745c000000000024f43d` | `0x0000000006442ce7000000000914e5e4000000000192745c000000000024f43d` | PASS    |
| `WWXRP_FACTORS_N3_PACKED` | `0x000000000a96251f000000000dd6ad96000000000228fcb000000000002de0ce` | `0x000000000a96251f000000000dd6ad96000000000228fcb000000000002de0ce` | PASS    |
| `WWXRP_FACTORS_N4_PACKED` | `0x0000000011ba25db00000000151a90e70000000002fdeaff0000000000399efe` | `0x0000000011ba25db00000000151a90e70000000002fdeaff0000000000399efe` | PASS    |

---

## Summary

| Family                            | Constants                                | PASS  | MISMATCH |
| --------------------------------- | ---------------------------------------- | ----- | -------- |
| Per-N payouts (M=0..7 packed)     | 5 × `QUICK_PLAY_PAYOUTS_N{0..4}_PACKED`  | 5     | 0        |
| Per-N M=8 jackpot                 | 5 × `QUICK_PLAY_PAYOUT_N{0..4}_M8`       | 5     | 0        |
| Per-N hero boost (M=2..7 packed)  | 5 × `HERO_BOOST_N{0..4}_PACKED`          | 5     | 0        |
| Per-N WWXRP factors (B=5..8 pkd)  | 5 × `WWXRP_FACTORS_N{0..4}_PACKED`       | 5     | 0        |
| **TOTAL**                         | 25                                       | **25** | **0**   |

**Verdict: PASS_ALL_25** — every script-emitted byte-string matches the planning-note
pasted `.sol` byte-string verbatim. Phase 267 Task 3 is **UNBLOCKED** to paste these
25 packed constants into `contracts/modules/DegenerusGameDegeneretteModule.sol` per
the locked decisions D-267-DIST-01 + D-267-EV-TARGET-01 + D-267-EV-PRECISION-01 +
D-267-WWXRP-SPLIT-01 + D-267-HERO-01..02 + D-267-CONSTPASTE-01.

**EV invariant evidence (from script):** per-N `basePayoutEV` measured at `99.99997`
to `100.00002` centi-x — drift `±0.0003 bps` (three orders of magnitude under the
user's 0.01% target). ETH bonus EV per N measured at `5.000000%` — drift `±0.0000 bps`.
Total ETH player RTP at MAX activity (9990 bps + 5% bonus) `= 104.9000%` identically
across all N — perfect cross-pick equality within rounding.

Phase 268 STAT-05 will empirically re-verify on-chain dispatch produces
`basePayoutEV = 100.00 ± 0.50 centi-x` per N over ≥1M draws (catches paste drift or
bit-rot the script-grep cannot detect).

---

## Re-run protocol (if any future run surfaces drift)

If a future re-run shows MISMATCH on any row, the source-of-truth is the script
(Fraction-exact derivation). The mismatch implies the planning-note `.sol` pasted
hex was hand-edited at some point and drifted from script output. Resolution path:

1. Surface the mismatch to the user with row-level evidence (script hex vs note hex).
2. Confirm the script is unchanged from the locked spec (per CONTEXT.md `<decisions>`
   D-267-DIST-01 + D-267-EV-TARGET-01 + D-267-EV-PRECISION-01 + D-267-WWXRP-SPLIT-01).
3. Patch the planning note's pasted hex to match the script output.
4. Re-run this verification.
5. Only proceed to (or re-run) Task 3 when ALL 25 grep pairs are PASS.

At HEAD (this run): no mismatch surfaced — script and planning note are byte-identical.
