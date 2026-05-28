---
phase: 334-spec-design-lock-mintdiv-reachability-proof-rngaudit-structu
plan: 02
subsystem: testing
tags: [solidity, audit, rng-freeze, whale-pass, mintmodule, grep-attestation, spec]

# Dependency graph
requires:
  - phase: 333-terminal (v49.0 closure)
    provides: the frozen v49.0-closure baseline b0511ca2 that contracts/ is byte-identical to
provides:
  - 334-GREP-ATTESTATION.md — every cited file:line confirmed/drift-corrected vs b0511ca2 (SC5)
  - 334-DESIGN-LOCK-WHALE-MINTDIV.md — settled whale-pass + MintModule shared signatures (SC1 whale/MintDiv slice)
  - 334-RNGAUDIT-STRUCTURE-SKETCH.md — R1->R4 + cold-start context-pack skeleton (SC4)
affects: [335-impl, 337-audit-protocol, 338-sweep, 336-tst]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "WHALE = convergence refactor onto EXISTING claimWhalePass/whalePassClaims (no parallel map)"
    - "grep-attest every anchor vs the frozen baseline; no by-construction survives un-checked"

key-files:
  created:
    - .planning/phases/334-spec-design-lock-mintdiv-reachability-proof-rngaudit-structu/334-GREP-ATTESTATION.md
    - .planning/phases/334-spec-design-lock-mintdiv-reachability-proof-rngaudit-structu/334-DESIGN-LOCK-WHALE-MINTDIV.md
    - .planning/phases/334-spec-design-lock-mintdiv-reachability-proof-rngaudit-structu/334-RNGAUDIT-STRUCTURE-SKETCH.md
  modified: []

key-decisions:
  - "Box-open whale pass converges onto the EXISTING whalePassClaims counter + claimWhalePass:1018 (D-20) — pendingWhalePasses is a relabel, not a new map"
  - "Q1 LOCKED (D-21): box-open whale pass adopts the flat grant shape; the <=level-10 40/lvl bonus band is DROPPED; single counter; economic value delta routed to the 338 SWEEP economic-analyst"
  - "MintModule :716 processed += writesUsed>>1 -> += take matching :502; the two loops stay separate (D-15)"
  - "Drift-corrected the _applyWhalePassStats caller set: WhaleModule:1032 is the claim caller, not a bundle caller; the bundle path does not call it"

patterns-established:
  - "Pattern 1: paper-only SPEC artifacts authored as final settled docs (no v1/simplified/for-now language)"
  - "Pattern 2: per-anchor grep/sed re-confirmation against the empty-diff baseline as the attestation method"

requirements-completed: [BATCH-01]

# Metrics
duration: 6min
completed: 2026-05-27
---

# Phase 334 Plan 02: SPEC Design-Lock + Grep-Attestation + RNGAUDIT Structure Summary

**Three settled SPEC artifacts: the whale-pass O(1) convergence onto the existing claimWhalePass/whalePassClaims machinery + the MintModule :716→:502 one-liner (SC1), the RNGAUDIT R1→R4 + cold-start context-pack sketch (SC4), and the complete grep-attestation table vs b0511ca2 with drift corrected (SC5).**

## Performance

- **Duration:** 6 min
- **Started:** 2026-05-27T21:51:09Z
- **Completed:** 2026-05-27T21:56:41Z
- **Tasks:** 3
- **Files modified:** 3 created (zero contracts/ touched)

## Accomplishments
- **SC5 (grep-attestation):** recorded the empty-diff baseline identity (`git diff b0511ca2 HEAD -- contracts/` = 0 lines → working tree IS the frozen contract baseline), then re-confirmed every cited anchor with grep/sed — correcting `_livenessTriggered` def to Storage:1213 (`:571` is a gate call-site), the AfKing `Sub` struct body to `:86-93`, and the `_applyWhalePassStats` caller set; surfaced the existing-machinery anchors (claimWhalePass:1018, whalePassClaims writers, _queueWhalePassClaimCore:45, the two processTicketBatch callers AdvanceModule:561/:1496); ends with the no-"by-construction"-survives-unchecked attestation.
- **SC1 (whale/MintDiv design-lock):** settled the convergence onto the existing `whalePassClaims` counter + `claimWhalePass(address player)` at WhaleModule:1018 (D-20, no parallel map); recorded the box-open change as a single O(1) `whalePassClaims += grant` replacing the `_activateWhalePass:1240` 100-loop with NO `mintPacked_` write at open; locked Q1 per D-21 (flat shape, 40/lvl bonus band dropped, value delta to 338) with no scope-reduction language; recorded the D-01 hard constraint (claim never auto-triggered), gameOver-forfeit (D-23), WHALE-03 autoOpen retirement (D-07), and the `:716`→`:502` MintModule alignment (D-15).
- **SC4 (RNGAUDIT sketch):** fixed the freeze-invariant target, the four exempt entry points, the R1→R4 sequence, the cold-start context-pack skeleton, and the no-answer-key / package-only / model-agnostic framing — flagged as the Phase-337 authoring target against the FROZEN post-v50 tree.

## Task Commits

Each task was committed atomically (gitignored `.planning/` artifacts force-added with `git add -f`):

1. **Task 1: Grep-attestation table vs b0511ca2 (SC5)** - `8f7d2e99` (docs)
2. **Task 2: Whale-pass + MintModule shared signatures (SC1)** - `5a95ea8f` (docs)
3. **Task 3: RNGAUDIT external-protocol structure sketch (SC4)** - `601522c1` (docs)

## Files Created/Modified
- `.planning/phases/334-.../334-GREP-ATTESTATION.md` - The complete attestation table (CONTEXT.md anchors + newly-surfaced existing-machinery anchors + VRF/lock anchors), the empty-diff baseline identity, the drift summary, and the no-by-construction attestation.
- `.planning/phases/334-.../334-DESIGN-LOCK-WHALE-MINTDIV.md` - The settled whale-pass + MintModule signatures: convergence onto existing machinery, Q1 LOCKED, the O(1) box-open record, the claim hard constraint, gameOver-forfeit, WHALE-03, the :716→:502 alignment, and the Claude's-discretion IMPL items.
- `.planning/phases/334-.../334-RNGAUDIT-STRUCTURE-SKETCH.md` - The Phase-337 authoring target: freeze invariant, exempt entry points, R1→R4, context-pack skeleton, and the external-audit framing.

## Decisions Made
- Recorded all decisions as final/settled (per the plan's authoring guidance the substance was already established in 334-RESEARCH.md / CONTEXT.md; this plan formalized it). No new design decisions were opened.
- During source re-verification (Task 1) the `_applyWhalePassStats` call-site set was found to differ from CONTEXT.md's labelling: `WhaleModule:1032` is the `claimWhalePass` caller (the deferred-claim apply itself), NOT a separate "bundle purchase" immediate-apply caller, and the bundle path `_purchaseWhaleBundle:194` does not call `_applyWhalePassStats` at all. The accurate set is exactly three sites (LootboxModule:1247 box-open → moves; WhaleModule:1032 claim → untouched; DecimatorModule:588 Decimator → untouched). Recorded as a drift correction in both the attestation table and the design-lock, honoring the no-"by-construction" floor.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Corrected a stated anchor inaccuracy during grep-attestation**
- **Found during:** Task 1 (Grep-attestation table)
- **Issue:** CONTEXT.md / 334-RESEARCH.md described `WhaleModule:1032` as an `_applyWhalePassStats` "bundle purchase" caller that stays immediate-apply alongside DecimatorModule:588. Source re-confirmation showed `:1032` is the call INSIDE `claimWhalePass` (the deferred claim), and the bundle purchase path does not call `_applyWhalePassStats`. Leaving the inaccurate labelling would violate the `feedback_verify_call_graph_against_source` floor (the exact "no by-construction survives un-checked" requirement this SPEC enforces).
- **Fix:** Recorded the corrected three-site call set in 334-GREP-ATTESTATION.md (§2/§4) and refined the D-04 "untouched callers" statement in 334-DESIGN-LOCK-WHALE-MINTDIV.md §2 (box-open caller moves; WhaleModule:1032 IS the claim; DecimatorModule:588 is the genuine remaining immediate-apply caller). The substance of D-04 is unchanged.
- **Files modified:** the two artifacts above (no contracts/ touched).
- **Verification:** `grep -rn "_applyWhalePassStats(" contracts/` confirms exactly three call sites (LootboxModule:1247, WhaleModule:1032, DecimatorModule:588).
- **Committed in:** `8f7d2e99` (Task 1) + `5a95ea8f` (Task 2)

---

**Total deviations:** 1 auto-fixed (1 bug — anchor-accuracy correction)
**Impact on plan:** The correction is required by the phase's own attestation floor; it sharpens the design-lock without changing any decision. No scope creep. The other anchor corrections the plan explicitly directed (_livenessTriggered :1213, Sub :86-93, processFutureTicketBatch :393) were recorded as planned.

## Issues Encountered
- Task 3 verify initially failed because the literal lowercase string "no answer key" was not present (the doc had "No answer key."). Added the verbatim constraint string; verify passed. No design impact.

## User Setup Required
None - paper-only SPEC; no external service configuration required.

## Next Phase Readiness
- **IMPL 335** can re-author the single batched contracts/ diff (whale-pass O(1) + MintModule one-liner) against the settled signatures with zero "by construction" assumptions. The producer-before-consumer edit-order map is in 334-RESEARCH.md (D-18).
- **Phase 337** has the RNGAUDIT structure target fixed; it authors the kit against the FROZEN post-v50 tree.
- **Phase 338 SWEEP** must sign off the Q1 economic value delta (box-open whale-pass reward reduction from dropping the ≤10 40/lvl bonus band) and the claim-timing degree of freedom (D-06/D-21).
- This plan (334-02) is the cross-cutting BATCH-01 slice. The other 334 obligations (WHALE-04 freeze proof, MINTDIV-01 verdict doc) are covered by their own SPEC artifacts / the research conclusions; this plan did not author them.

## Self-Check: PASSED

- All three artifacts + SUMMARY.md exist on disk (FOUND).
- All three task commits exist in git log: `8f7d2e99`, `5a95ea8f`, `601522c1` (FOUND).
- `grep -rn "_applyWhalePassStats(" contracts/` = exactly 3 call sites (drift correction verified).
- `git diff b0511ca2 HEAD -- contracts/` = 0 lines (zero contracts/ modified).

---
*Phase: 334-spec-design-lock-mintdiv-reachability-proof-rngaudit-structu*
*Completed: 2026-05-27*
