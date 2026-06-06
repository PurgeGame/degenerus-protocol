---
phase: 375-spec-design-lock-open-knobs-anchor-re-attestation-vs-2bee6d6
plan: 01
subsystem: testing
tags: [anchor-re-attestation, spec-integrity, bit-packing, solvency, smart-contract-audit, 2bee6d6f]

# Dependency graph
requires:
  - phase: v60.0-closure
    provides: "frozen baseline 2bee6d6f (the IMPL subject all anchors are re-attested against)"
provides:
  - "375-ANCHOR-REATTESTATION.md — re-attested anchor table (29 anchors across 13 files, CONFIRMED/CORRECTED + git evidence vs 2bee6d6f)"
  - "the 4 CORRECTED baseline lines the SPEC (Plan 02) must adopt (claimablePool decl 365, _purchaseForWith 1093, _recordLootboxMintDay 1000, sDGNRS read 932)"
  - "purchaseWith DEAD-confirm verdict (leave untouched at IMPL)"
  - "self-smite HARMLESS-by-design verdict (shared-counter reasoning chain)"
  - "SOLVENCY accessor-invariant home pinned (PACK accessor layer; Storage:358/365/851 + PayoutUtils:25/39/63 + GameAfkingModule afking pair) for SEC-02 (378)"
  - "empirical [215-222] free-gap proof (header [215-227] unused + all 12 mintPacked_ writes field-isolated RMW) for CURSE-01"
affects: [375-02-PLAN (SPEC fold), 376-IMPL (edit targets), 378-TST (SEC-02 SOLVENCY anchor)]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "git-grounded anchor re-attestation: read every file:line FROM the frozen baseline via git grep/show, never from the working tree (which is ahead)"
    - "empirical bit-gap proof: enumerate every slot writer + show field-isolated RMW (setPacked keystone) rather than asserting a gap is free"

key-files:
  created:
    - .planning/phases/375-spec-design-lock-open-knobs-anchor-re-attestation-vs-2bee6d6/375-ANCHOR-REATTESTATION.md
  modified: []

key-decisions:
  - "purchaseWith is DEAD at 2bee6d6f (def:858 + interface:242 + 3 comments; no call/selector/dispatch) -> AFPAY leaves it untouched, lands in _purchaseForWith/_processMintPayment"
  - "self-smite is harmless-by-design (shared curse counter only lowers the activity score floored 0; caller burns own 200 BURNIE; no bounty/score-floor/positive-EV path)"
  - "SOLVENCY-01 invariant home = the PACK accessor layer (D-01); SEC-02 anchors on Storage:358/365/851 + PayoutUtils:25/39/63 rather than the scattered debit/credit sites"

patterns-established:
  - "Anchor cite drift: the v60.0 baseline is an ancestor of the 2026-06-06 doc-HEAD, so most cites are exact/within a few lines; 4 needed material correction"

requirements-completed: [SPEC-01]

# Metrics
duration: 7min
completed: 2026-06-06
---

# Phase 375 Plan 01: Anchor Re-Attestation vs `2bee6d6f` Summary

**Every contract anchor in `375-CONTEXT.md` re-grounded on the frozen baseline `2bee6d6f` via git (29 anchors, 4 CORRECTED), plus the three SPEC verification items resolved: `purchaseWith` DEAD, self-smite harmless, SOLVENCY home pinned to the PACK accessor layer.**

**Artifact:** `.planning/phases/375-spec-design-lock-open-knobs-anchor-re-attestation-vs-2bee6d6/375-ANCHOR-REATTESTATION.md`

## Performance

- **Duration:** 7 min
- **Started:** 2026-06-06T20:56:13Z
- **Completed:** 2026-06-06T21:04:10Z
- **Tasks:** 2
- **Files modified:** 1 (the `.planning/` artifact; ZERO `contracts/*.sol`)

## Accomplishments

- **Re-attested 29 anchors across 13 files** against `2bee6d6f` with per-row CONFIRMED/CORRECTED status + the exact `git grep`/`git show` evidence (grouped by file). Every CONTEXT.md `<canonical_refs>` "Contract anchors" symbol appears; 0 dropped. 4 to-be-added symbols (`AfkingSpent`, `decurse`/`smite`, `CURSE_COUNT_CAP`, `MASK_8`/`CURSE_COUNT_SHIFT`) correctly verified ABSENT at the baseline.
- **Found and corrected 4 material line-drifts** the SPEC must adopt (see below) — most notably the `claimablePool uint128` decl is at **365**, NOT the cited ~:838-839 (which is the `_setCurrentPrizePool` width-safety doc-comment); the cure host is `_purchaseForWith` @ **1093**, not the mis-named `_purchaseWithFor` ~:1285.
- **Empirically proved the `[215-222]` free-gap** for `CURSE_COUNT_SHIFT = 215`: the BitPackingLib header documents `[215-227] (unused)`, `AFFILIATE_BONUS_POINTS_SHIFT = 209` ends bit 214, `LEVEL_UNITS_SHIFT = 228`; and ALL 12 `mintPacked_` write sites are field-isolated RMW (the `setPacked` keystone `(data & ~(mask<<shift)) | ((value&mask)<<shift)`), so no full-slot writer clobbers 215-222.
- **Resolved all three SPEC verification items** with baseline-grounded evidence (verdicts below).

## Task Commits

Each task was committed atomically (docs-only, force-added past the `.planning/` gitignore):

1. **Task 1: Re-attest every contract anchor vs `2bee6d6f`** - `f6db9181` (docs)
2. **Task 2: Resolve the three SPEC verification items** - `8e4edff5` (docs)

**Plan metadata:** _(committed in the final docs commit with SUMMARY/STATE/ROADMAP)_

## Files Created/Modified

- `375-ANCHOR-REATTESTATION.md` - the re-attested anchor table (29 rows grouped by 13 files) + the `[215-222]` free-gap proof + the three SPEC verification-item sections + a re-attestation summary.

## Decisions Made

- **`purchaseWith` DEAD → leave untouched at IMPL.** Five references at `2bee6d6f`: def (`MintModule:858`), interface (`IDegenerusGameModules:242`), and 3 stale doc-comments (`AdvanceModule:759`, `MintModule:1122`, `GameAfkingModule:1097`). The `.selector`/call-site grep returned only a parenthetical in a comment — no dispatch. The AFPAY waterfall lands in the live `_purchaseForWith` (1093) / `_processMintPayment` (`DegenerusGame.sol:1054`).
- **Self-smite HARMLESS-by-design.** The shared `uint8` curse counter only lowers the activity score (single APPLY @ `MintStreakUtils:320 scoreBps = bonusBps`, floored 0 — never beneficial); `smite` burns the caller's own 200 BURNIE (`burnCoin … onlyGame @ BurnieCoin:572`); `_bountyEligible` (`:30`) does not read the counter → no bounty/score-floor/positive-EV path. Matches STRIDE T-375-03 (accept).
- **SOLVENCY-01 home = the PACK accessor layer** (D-01). Re-attested enforcement surface: invariant statement @ `DegenerusGameStorage.sol:358`, `claimablePool` decl @ **365**, canonical `_settleClaimableShortfall` @ **851** (→ `_settleShortfall` at IMPL), the 2 centralized claimable credits @ `DegenerusGamePayoutUtils.sol:25/39/63`, the afking credit/debit pair in `GameAfkingModule` (337 / ~791). SEC-02 (378) anchors here.

## CORRECTED anchors (the SPEC must cite the baseline line)

1. `claimablePool` `uint128` decl: cited ~:838-839 (a `_setCurrentPrizePool` doc-comment) → actual decl **@ 365** (SOLVENCY invariant comment @ 358).
2. cure-site function: cited `_purchaseWithFor` ~:1285 → actual host **`_purchaseForWith` def @ 1093** (line 1285 is inside its body).
3. `_recordLootboxMintDay`: cited ~:983 → actual def **@ 1000** (call site 858).
4. sDGNRS redemption activity-score read: cited ~:942 → actual **@ 932**.

All other anchors CONFIRMED at/within a few lines of their cite (the baseline is an ancestor of the 2026-06-06 doc-HEAD).

## Deviations from Plan

None - plan executed exactly as written. (No bugs, no missing critical functionality, no blocking issues, no architectural changes. The 4 CORRECTED anchors are the expected *output* of the re-attestation, not deviations.)

## Issues Encountered

- The plan's `read_first` cited `PLAN-V61-DEITY-SMITE.md` §4 and `PLAN-V61-AFKING-AS-PAYMENT-SOURCE.md` §6/§8 — both read directly (not the `.planning/PLAN-*` shorthand). CONTEXT.md's anchor shorthand `_purchaseWithFor` resolved to the actual `_purchaseForWith` via a `git grep 'function _purchase'`; recorded as CORRECTED. No blockers.

## Next Phase Readiness

- **Plan 02 (the SPEC fold)** can consume `375-ANCHOR-REATTESTATION.md` directly: the anchor table provides baseline-true `file:line` edit targets for the single 376 IMPL diff, the 4 CORRECTED lines flag where CONTEXT.md drifted, and the three verdicts close the open SPEC-execution items.
- **376 IMPL:** `CURSE_COUNT_SHIFT = 215` is cleared for the `[215-222]` gap; `purchaseWith` confirmed safe to ignore; the cure host is `_purchaseForWith` (1093), the curse APPLY chokepoint is `MintStreakUtils:320`.
- **378 SEC-02:** the SOLVENCY-01 identity home is pinned to the PACK accessor layer with re-attested baseline lines.

## Self-Check: PASSED

- `375-ANCHOR-REATTESTATION.md` — FOUND
- `375-01-SUMMARY.md` — FOUND
- Task 1 commit `f6db9181` — FOUND
- Task 2 commit `8e4edff5` — FOUND
- `purchaseWith` DEAD verdict + self-smite HARMLESS verdict + 4 CORRECTED anchors — present
- `git status --porcelain contracts/` — empty (ZERO `contracts/*.sol` modified)

---
*Phase: 375-spec-design-lock-open-knobs-anchor-re-attestation-vs-2bee6d6*
*Completed: 2026-06-06*
