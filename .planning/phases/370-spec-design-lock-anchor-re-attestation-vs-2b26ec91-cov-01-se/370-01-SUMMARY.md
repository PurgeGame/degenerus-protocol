---
phase: 370-spec-design-lock-anchor-re-attestation-vs-2b26ec91-cov-01-se
plan: 01
subsystem: v59.0 design-lock (paper-only SPEC)
tags: [spec, design-lock, anchor-attestation, solvency, f-03-variant, window-01]
requires:
  - audit/FINDINGS-v58.0.md (the 7 council findings + fix sketches)
  - .planning/PLAN-PASS-STAT-FRONTLOAD.md (Change A/B/C design)
  - frozen contract subject 2b26ec91 (read via git show / git grep only)
provides:
  - the anchor re-attestation table (7 groups, 24 anchors grep-verified vs 2b26ec91)
  - the F-03 / SOLV-01 fix-variant LOCK (variant a) + frozen-body rationale
  - the producer-before-consumer batched-diff edit-order map (9 IMPL reqs)
  - the WINDOW-01 pre-edit verification (every frozenUntilLevel hit classified)
affects:
  - Phase 371 IMPL (authors the ONE batched diff against the AS-FOUND anchors + locked variant + edit order)
tech-stack:
  added: []
  patterns: [grep-attestation-vs-frozen-sha, producer-before-consumer-edit-order]
key-files:
  created:
    - .planning/phases/370-spec-design-lock-anchor-re-attestation-vs-2b26ec91-cov-01-se/370-01-SPEC.md
  modified: []
decisions:
  - "F-03 / SOLV-01 LOCKED to variant (a): return the BAF whale-pass remainder from _queueWhalePassClaimCore and fold into claimableDelta so memFuture -= claimed debits futurePrizePool; variant (b) push-back rejected (the BAF memFuture cached-local at AdvanceModule:801 is clobbered by the single :968 writeback, so a mid-loop _setFuturePrizePool is silently overwritten)"
  - "SALV-01 fix uses custom-error widening if (n == 0 || n > type(uint32).max) revert E(); at MintStreakUtils:174 (repo uses revert E() not require)"
  - "STREAK-01 promotes MINT_STREAK_LAST_COMPLETED_SHIFT = 160 into BitPackingLib — confirmed a clean no-conflict add (the bit-layout doc already reserves [160-183], [154-159] unused, brackets WHALE_BUNDLE_TYPE_SHIFT=152 / HAS_DEITY_PASS_SHIFT=184)"
metrics:
  tasks: 2
  files_created: 1
  contracts_modified: 0
  spec_lines: 329
  anchors_attested: 24
  completed: 2026-06-04
---

# Phase 370 Plan 01: v59.0 Design-Lock SPEC Summary

Produced the v59.0 design-lock SPEC (`370-01-SPEC.md`, 329 lines) so Phase 371 IMPL can author
ONE fully-reconciled batched contract diff with zero "by construction" assumptions: every cited
`file:line` anchor re-attested against the frozen `2b26ec91`, the open F-03 / SOLV-01 fix variant
LOCKED to variant (a) with a frozen-body rationale, the producer-before-consumer edit order mapped
across all 9 IMPL reqs, and the WINDOW-01 pre-edit verification complete. Paper-only — ZERO
`contracts/*.sol` (`git diff 2b26ec91 HEAD -- contracts/` is empty).

## What was built

**Task 1 — Anchor re-attestation (commit `8025f06e`).** A 7-group table (SALV / AFAFF / SOLV /
PRESALE + Change-A/B/C) with as-cited / as-found / drift / corrected / role columns, every row
grep/show-verified against `2b26ec91`. 24 distinct anchors attested. Drifts are ±1–2 lines (the
v58.0 council read approximate context-pack cites) plus two structural corrections:
- The F-03/F-04 `claimWinnings :1588` cite resolves to `DegenerusGame.sol:1588` (not a module).
- The decimator `:392-399` / `:596` decl cites drift to the AS-FOUND `:385` / `:580` function
  declarations.

Key AS-FOUND lines the IMPL targets: SALV quote-loop `n==0` at `MintStreakUtils:174`; AFAFF
accrual at `GameAfkingModule:879` (siblings divide at `:825`/`:887`); F-03 core
`_queueWhalePassClaimCore` at `PayoutUtils:45-60` (returns nothing, `remainder` bumps pool
inline at `:58`); BAF caller `memFuture -= claimed` at `AdvanceModule:902` (folds at `:972`);
F-04 site `DecimatorModule:596`; PRESALE flip at `GameAfkingModule:397-398`; the 6 WINDOW
comparisons; the STREAK shift local at `MintStreakUtils:19` (+4 refs `:22/:72/:94/:105`); the
CENTURY x0 term at `WhaleModule:414`.

**Task 2 — F-03 variant lock + edit-order map + WINDOW-01 verification (commit `d3a6d0b6`).**
- **F-03 / SOLV-01 LOCKED to variant (a)** — return `remainder` from `_queueWhalePassClaimCore`,
  fold into the BAF caller's `claimableDelta` so the existing single `memFuture -= claimed` /
  `claimablePool += claimableDelta` accounting debits `futurePrizePool` for it (mirrors
  `_addClaimableEth`, which credits via `_creditClaimable` and returns the wei for the caller to
  fold). **Variant (b) rejected** on a decisive structural fact: in the BAF path `futurePrizePool`
  is a stale cached local `memFuture` (read once at `AdvanceModule:801`, written back with a single
  `_setPrizePools` at `:968`), so a mid-loop `_setFuturePrizePool` push-back inside `runBafJackpot`
  would be silently CLOBBERED. `_processSoloBucketWinner` can use the push-back shape only because
  it runs outside that cached-`memFuture` window. SOLV-02 (F-04) is confirm-only (single
  `claimablePool += uint128(remainder);` at `DecimatorModule:596`, no variant).
- **Edit-order map** — two producer-before-consumer chains: STREAK-01 (`BitPackingLib` shift
  promotion) BEFORE STREAK-02 (`_withPassStreakFrontLoad` helper); SOLV-01 return-value
  (`PayoutUtils:45`) BEFORE the BAF caller fold (`JackpotModule:1949`). The 6 remaining reqs
  (SALV-01, AFAFF-01, SOLV-02, PRESALE-01, WINDOW-01, CENTURY-01) are order-free.
- **WINDOW-01 pre-edit verification** — the exhaustive `frozenUntilLevel` grep classifies every
  hit as FLIP / EXTENSION / EARLY-RENEWAL / UNRELATED. Exactly 6 FLIP comparisons (matching the
  Change-A table, no missed reader); the 3 EXTENSION sites (`> targetFrozenLevel` renewal max at
  `WhaleModule:221`, `Storage:1070`, `Storage:1151`) and the 1 EARLY-RENEWAL guard
  (`WhaleModule:428` `> currentLevel + 7`) stay UNTOUCHED. The afking eviction boundary is
  re-confirmed inclusive-through-`validThroughLevel` (`processSubscriberStage` evicts only at
  `currentLevel > sub.validThroughLevel`, `:1191`); the flip makes freeze/floor/bonus/view cover
  1–10 inclusively to MATCH it, fixing the latent level-10 `levelCount` over-count.

## Deviations from Plan

None — plan executed exactly as written. Both tasks paper-only; all anchors grep-verified against
`2b26ec91`; no contract read from the working tree for attestation.

One incidental tooling note (not a deviation): `.planning/` is gitignored in this repo, so the
SPEC and SUMMARY are committed with `git add -f` (matching how the tracked PLAN/STATE files were
force-added). The contract-commit guard hook was never tripped — this plan commits zero
`contracts/*.sol`.

## Anchor drift verdict

7 anchor groups attested, 7 carry drift on ≥1 line (all corrected to AS-FOUND in the SPEC),
0 unverified. The IMPL diff targets the AS-FOUND lines, not the council's approximate cites.

## Self-Check: PASSED

- `370-01-SPEC.md` exists (329 lines, > 80-line min) — FOUND
- commit `8025f06e` (Task 1) — FOUND
- commit `d3a6d0b6` (Task 2) — FOUND
- `git diff 2b26ec91 HEAD -- contracts/` empty (frozen subject untouched) — CONFIRMED
- SPEC contains the anchor table (`2b26ec91` + `drift`), the F-03 variant (`F-03`/`SOLV-01`),
  the edit-order map (`producer-before-consumer`), and the WINDOW-01 verification
  (`frozenUntilLevel` + `validThroughLevel`, "exactly 6 FLIP") — CONFIRMED
