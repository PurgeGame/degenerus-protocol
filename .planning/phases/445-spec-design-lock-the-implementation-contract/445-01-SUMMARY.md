---
phase: 445-spec-design-lock-the-implementation-contract
plan: 01
subsystem: v71.0-foilpack-spec
tags: [spec, design-lock, rarity-pmf, activity-curve, foilboostbps, economics]
requires:
  - 445-RESEARCH.md §A (rarity PMF, V1 PASS)
  - 445-RESEARCH.md §C (foilBoostBps curve, V1 PASS)
  - 445-CONTEXT.md D-02 / D-03
provides:
  - 445-SPEC-A-economics.md (locked rarity-PMF + foilBoostBps coefficient sections)
affects:
  - 445-04 (SPEC consolidation consumes this section)
  - 446 IMPL (writes traitFromWordFoil/packedTraitsFoil + foilBoostBps from this section, no further math)
tech-stack:
  added: []
  patterns:
    - sibling-producer clone of packedTraitsDegenerette/_degTrait (color stage only)
    - /15360 = 256x60 integer cutoff ladder (clears /5 taper + 3-way common split)
    - 4-anchor/3-segment piecewise-linear bps curve on existing ActivityCurveLib knees
key-files:
  created:
    - .planning/phases/445-spec-design-lock-the-implementation-contract/445-SPEC-A-economics.md
  modified: []
decisions:
  - "D-03 realized as linear-in-rare-rank taper: w={7:5/5,6:4/5,5:3/5,4:2/5,3:1/5}, commons 0/1/2 sole funding sink"
  - "p_gold=(2/256)*M locked invariant; gold lands exactly on 120*M on the /15360 ladder"
  - "D-02 realized as FOIL_MIN/K/VA/VB/MAX = 20000/300+50000/55000/60000 on the existing 500/30000 knees; 350 NOT pinned"
  - "RARE-03 freeze link: multBps frozen at buy from cachedScore (MintModule:1709), applied at resolve, never live-read"
metrics:
  duration: ~6m
  completed: 2026-06-19
  tasks: 2
  files: 1
  commits: 2
---

# Phase 445 Plan 01: SPEC Economics (rarity PMF + foilBoostBps curve) Summary

Locked the economics half of the v71.0 Foil Pack design-lock SPEC — the tapered sibling-producer
rarity PMF (`/15360` integer cutoff ladder, `p_gold=(2/256)·M`) and the `foilBoostBps(score)`
activity curve (5 constants, 4 segment closed forms on the existing `ActivityCurveLib` knees) — both
coefficient-exact so Phase 446 IMPL is mechanical.

## What was built

`.planning/phases/445-spec-design-lock-the-implementation-contract/445-SPEC-A-economics.md` (243 lines),
authored across two atomic tasks:

### Task 1 — rarity PMF (commit `def81a48`; RARE-01/02/04, FOIL-05)
- The two sibling producers `traitFromWordFoil(uint64 rnd, uint256 multBps)` /
  `packedTraitsFoil(uint256 rand, uint256 multBps)` stated as clones of
  `packedTraitsDegenerette` / `_degTrait` (`DegenerusTraitUtils.sol:201-223`) — per-quadrant
  `[QQ][CCC][SSS]`, 4 bytes packed into a `uint32`, symbol uniform `1/8` from `rnd>>32 & 7`. **Only the
  color stage changes**; the v70-frozen `weightedColorBucket`/`traitFromWord`/`packedTraitsFromSeed`
  are explicitly NOT edited (RARE-01).
- The taper rule `boost(c) = 1 + (M−1)·w_c` with rare-rank weights `w={7:5/5, 6:4/5, 5:3/5, 4:2/5,
  3:1/5}`, the three 25% commons (0/1/2) as the sole funding sink, gold (color 7) taking the full
  multiplier so `p_gold = (2/256)·M` exactly (×6 ⇒ 12/256 = 4.6875% ≈ 4.7%).
- The resolve mechanism as the `/15360 = 256×60` integer cutoff ladder with
  `width15360[c] = base[c]·60·(50000 + (multBps−10000)·w5[c])/50000`, `rem` split `rem/3` with the
  `rem mod 3` residual to the first common, gold = `120·M`.
- The V1 validity attestation: ladder sums to exactly 15360 with all 8 widths ≥0 for every integer
  `multBps ∈ [20000,60000]` (40,001 grid points, 0 mismatches/0 negatives); PMF valid to M≈8.8689, so
  "worst case WITHIN the locked [2,6] range" (wording correction carried, NOT "binding case M=6").
- The per-tier probability table at M=2.0/2.5/5.0/6.0 verbatim from RESEARCH §A, plus the
  gold-odds-vs-10-tickets anchors (≈22.3% @ ×2, ≈tie @ ×2.485, 53.6% @ ×6).

### Task 2 — foilBoostBps(score) curve (commit `9c3b891c`; RARE-02/03, FOIL-05)
- The 5 constants `FOIL_MIN_BPS=20000`, `FOIL_K_POINTS=300`, `FOIL_VA_BPS=50000`,
  `FOIL_VB_BPS=55000`, `FOIL_MAX_BPS=60000` to add to `ActivityCurveLib`, reusing the existing
  `ACTIVITY_SEG_B_KNEE_POINTS=500` and `ACTIVITY_EFFECTIVE_CAP_POINTS=30000` knees.
- The 4 segment closed forms: Seg A `20000+100·score`, Seg B `50000+25·(score−300)`, Seg C
  `55000+(score−500)·5000/29500`, saturation `60000`, with explicit `score==0` and `score≥30000`
  guard branches (no endpoint interpolation rounding).
- The value table (0→20000, 50→25000, 100→30000, 300→50000, 350→51250, 500→55000, 5000→55762,
  30000→60000), with the `350→51250` row flagged **ILLUSTRATIVE / NOT pinned** (D-02).
- RARE-03 freeze semantics: `multBps` frozen at buy from the same `cachedScore` source the mint path
  uses (`DegenerusGameMintModule.sol:1709`), applied at resolve, never live-read.
- The V1 invariants: monotone non-decreasing over [0,30001], saturates flat at ×6,
  `foilBoostBps(50)=25000` tie anchor.

## Deviations from Plan

None — plan executed exactly as written. Both `type="auto"` tasks transcribed the RESEARCH §A / §C
reconciled values verbatim; no bugs, missing functionality, or blocking issues were encountered (the
plan is paper-only SPEC authoring). The only operational note: `.planning/` is gitignored in this repo,
so the SPEC file and this SUMMARY were force-added (`git add -f`) per the established repo pattern — a
mechanical commit detail, not a content deviation.

## Verification

- Task 1 automated verify: PASS (`/15360`, `5/5`/`w_7`, `p_gold`/`2/256`/`120`, `packedTraitsFoil` all present).
- Task 2 automated verify: PASS (`FOIL_MIN_BPS`, `FOIL_MAX_BPS`, `20000+100`/`100·score`, `cachedScore`,
  `350…NOT`/`illustrative` all present).
- Plan-level verify: PASS — both the rarity-PMF and foilBoostBps sections present; `/15360`, the `w`
  weights, `p_gold=(2/256)·M`, and the 5 curve constants all string-present.
- `git diff --quiet -- contracts/` → CLEAN (no `contracts/*.sol` touched; paper-only plan).
- No `.planning/STATE.md` or `.planning/ROADMAP.md` write (orchestrator owns those).
- Stub scan: NONE (no TODO/FIXME/placeholder/coming-soon).

## Known Stubs

None.

## Threat Flags

None — this plan authors a `.planning/` design-lock SPEC section only; it introduces no code, no
network endpoint, no auth path, no file access, and no schema/storage change at a trust boundary. The
storage-layout and security design basis (`foilRecord` packing, the steer-proof 4-of-4 gate, the ETH
≤10% cap) live in other 445 plans / sections and are attested downstream at 448/449.

## Self-Check: PASSED

- `445-SPEC-A-economics.md` — FOUND.
- `445-01-SUMMARY.md` — FOUND.
- Commits `def81a48` (Task 1), `9c3b891c` (Task 2), `6ed615a8` (SUMMARY) — all FOUND in `git log`.
- `git diff HEAD~3 HEAD` touches exactly the two intended files (354 insertions); `STATE.md` /
  `ROADMAP.md` ABSENT from my commits (orchestrator-owned; the pre-existing `STATE.md` modification
  remains unstaged).
- `git diff --quiet -- contracts/` → CLEAN.
