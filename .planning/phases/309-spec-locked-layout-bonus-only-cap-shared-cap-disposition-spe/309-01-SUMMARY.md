---
phase: 309-spec-locked-layout-bonus-only-cap-shared-cap-disposition-spe
plan: 01
subsystem: lootbox-evcap-spec
tags: [spec, v45.0, lootbox, ev-cap, V-081, packed-storage, freeze-invariant]
requires:
  - "REQUIREMENTS.md SPEC-01..03 (locked design)"
  - "v45-lootbox-evcap-fix-plan.md Change 1 + Change 2 (uint96 superseded)"
  - "Contract HEAD MILESTONE_V44_AT_HEAD_6f0ba2963a10654ba554a8c333c5ee80c54a8349"
provides:
  - "309-SPEC.md §0 grep-verified call-graph evidence matrix"
  - "309-SPEC.md §1 SPEC-01 locked packed uint256 layout (lootboxPurchasePacked)"
  - "309-SPEC.md §2 SPEC-02 bonus-only cap (<= NEUTRAL early return)"
  - "309-SPEC.md §3 SPEC-03 allocation tally + openLootBox frozen-apply"
affects:
  - "Phase 310 IMPL (the locked contract spec it implements)"
  - "Phase 309 Plan 02 (§4 SPEC-04 appends to this same file)"
tech-stack:
  added: []
  patterns:
    - "Grep-verified file:line evidence with matched substring per cited ref"
    - "Packed uint256 word: score+1 / adjustedPortion(uint64) / baseLevel+1"
key-files:
  created:
    - ".planning/phases/309-spec-locked-layout-bonus-only-cap-shared-cap-disposition-spe/309-SPEC.md"
  modified: []
decisions:
  - "adjustedPortion locked uint64 (fix-plan uint96 SUPERSEDED) — D-01"
  - "baseLevel co-packed into the word; lootboxBaseLevelPacked removed → net -1 slot — D-02"
  - "lootboxDay co-pack REJECTED (seed input, freeze hard line) — D-03"
  - "Rename lootboxEvScorePacked → lootboxPurchasePacked (uint256) — D-05"
  - "Bonus-only cap: <= NEUTRAL early return draws no cap, all 3 callers — D-08"
metrics:
  duration: "~3 min"
  completed: "2026-05-20"
  tasks: 3
  files: 1
---

# Phase 309 Plan 01: §0 Evidence + SPEC-01 Layout + SPEC-02 Cap + SPEC-03 Allocation Summary

Authored §0-§3 of `309-SPEC.md`: a grep-verified call-graph evidence matrix against contract
HEAD `6f0ba296`, then the locked packed-`uint256` layout (`lootboxPurchasePacked`, net −1 slot),
the bonus-only `<= NEUTRAL` cap rule across all three callers, and the per-deposit allocation
tally with the cap-free `openLootBox` frozen-apply formula — zero contract/test mutations, zero
"by construction" claims.

## What Was Built

- **§0 Call-Graph Evidence (Task 1):** A grep-verified matrix (§0.A–§0.K) covering every
  `309-CONTEXT.md` canonical ref against HEAD with the matched substring and the line `grep -n`
  returned. Includes: four Storage declarations with key shapes; the three distinct
  `_applyEvMultiplierWithCap` call sites (559/675/711) vs the single definition (475); the
  cap-fn body SLOAD (487) / SSTORE (502); the three roll entry points + their frozen-score
  multiplier sources (558/674/710); the four seed-build sites; an EXHAUSTIVE enumeration of all
  three `lootboxDay` writers (Mint:991, Mint:1396-1397 BURNIE path, Whale:854); both flagged
  divergences (DIV-1 baseLevel `+1` vs `+2`; DIV-2 Mint gated vs Whale inline score write); and
  the no-by-construction attestation.
- **§1 SPEC-01 Layout (Task 2):** Locked the four-field word (`[0:16]` score+1, `[16:80]`
  adjustedPortion `uint64`, `[80:104]` baseLevel+1, `[104:256]` free), the `uint64` width proof
  with the fix-plan `uint96` marked SUPERSEDED, the baseLevel co-pack (net −1 slot), the
  `lootboxDay` rejection (seed input), the D-04 wrong-key-shape negative finding, the
  `lootboxPurchasePacked` rename, the `_packLootboxPurchase`/`_unpackLootboxPurchase` signatures,
  and the no-new-slot attestation.
- **§2 SPEC-02 Cap (Task 3):** Locked the `<= LOOTBOX_EV_NEUTRAL_BPS` early return returning
  `(amount * evMultiplierBps) / 10_000` (penalty/neutral apply in full, never draw the cap; only
  `> NEUTRAL` draws), cited at all three call sites.
- **§3 SPEC-03 Allocation (Task 3):** Locked the per-deposit tally (`mult <= NEUTRAL` → store
  score+1 only; `mult > NEUTRAL` → `add = min(deposit, CAP - used)`, advance used, accumulate
  adjustedPortion), first-vs-subsequent deposit semantics across both Mint/Whale shapes, the
  `openLootBox` formula `scaled = mult <= NEUTRAL ? amount*mult/1e4 : adj*mult/1e4 + (amount - adj)`
  with no cap SLOAD/SSTORE + whole-slot zero-at-open, and IMPL-05 seed/`lootboxEth` preservation.

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | §0 Evidence — grep-verify every cited file:line | 4f743f68 | 309-SPEC.md |
| 2 | §1 SPEC-01 — lock packed uint256 layout | 4482dfa8 | 309-SPEC.md |
| 3 | §2 SPEC-02 cap + §3 SPEC-03 tally/open-apply | 5b8a9fad | 309-SPEC.md |

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 — Bug] Plan `<verified_head_facts>` line 621 amount-arg mismatch corrected**
- **Found during:** Task 1 (§0.F seed-build verification)
- **Issue:** The plan's `<verified_head_facts>` and CONTEXT.md `<code_context>` listed the
  `:621` seed as `keccak256(abi.encode(rngWord, player, day, amount))`. The ACTUAL HEAD source
  at `LootboxModule.sol:621` uses `amountEth` (a BURNIE→ETH-equivalent computed at line 612),
  because 621 is the BURNIE-lootbox open path, distinct from the ETH `openLootBox` at 517/545.
- **Fix:** Recorded the ACTUAL `amountEth` substring in §0.F with an explicit DISCREPANCY box
  (per the executor mandate to record actual greps, not trust pre-verified line numbers), and
  noted in §3.5 that IMPL-05 must preserve `amountEth` at 621. No code touched — documentation
  artifact only. This is the kind of inline-duplication drift the project rule
  `feedback_verify_call_graph_against_source` exists to catch.
- **Files modified:** 309-SPEC.md (spec content)
- **Commit:** 4f743f68

### Line-span clarifications (not deviations, recorded for IMPL precision)

- `lootboxBaseLevelPacked` declaration spans `Storage.sol:1374-1375` (type 1374, name 1375);
  `lootboxEvBenefitUsedByLevel` spans 1427-1428 (type 1427, name 1428) — both matched the plan.
- Mint baseLevel write is a 3-line statement (Mint:992-994). Mint score write is gated 1154-1155.
  Whale score write is inline 856-858. All matched the plan's flagged divergences.
- All other cited lines matched `<verified_head_facts>` exactly.

## Authentication Gates

None.

## Verification

- §0/§1/§2/§3 all present in `309-SPEC.md`; baseline HEAD string present.
- Both Mint/Whale divergences (DIV-1 baseLevel +1 vs +2; DIV-2 gated vs inline score) recorded
  in §0.I and re-referenced in §1.7 and §3.3.
- Exhaustive `lootboxDay` writer enumeration (Mint:991 + Mint:1396-1397 BURNIE + Whale:854) in §0.H.
- Three `_applyEvMultiplierWithCap` call sites (559/675/711) cited distinctly in §0.C and §2.2.
- `git status --porcelain contracts/ test/` returns no output across all three tasks — zero
  code/test mutations (the phase invariant).
- Zero "by construction" / "single fn reaches all paths" claims — §0.K attestation.

## Notes for Phase 309 Plan 02 (§4 SPEC-04)

- §0.E already grounds the word-independence anchor: `resolveLootboxDirect` (674) and
  `resolveRedemptionLootbox` (710) derive the multiplier from the FROZEN `activityScore`
  parameter, not `rngWord`. §0.D enumerates the cap-fn's only shared-mutable SLOAD/SSTORE
  (`lootboxEvBenefitUsedByLevel[player][lvl]`, 487/502) — the SLOAD-enumeration starting point
  D-11 requires. Plan 02 appends §4 to this same `309-SPEC.md`.

## Self-Check: PASSED

- 309-SPEC.md exists with §0/§1/§2/§3.
- 309-01-SUMMARY.md exists.
- Commits 4f743f68 / 4482dfa8 / 5b8a9fad all present in git log.
