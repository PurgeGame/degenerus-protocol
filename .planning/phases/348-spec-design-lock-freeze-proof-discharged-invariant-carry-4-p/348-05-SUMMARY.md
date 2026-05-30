---
phase: 348-spec-design-lock-freeze-proof-discharged-invariant-carry-4-p
plan: 05
subsystem: docs
tags: [spec, edit-order-map, producer-before-consumer, code-size, eip-170, freeze, afking-in-game, arch-04]

# Dependency graph
requires:
  - phase: 348-01 (GREP-ATTESTATION)
    provides: the re-pinned live anchors for every edit site (box-seed abi.encode at LB:534, STAGE insertion :272-273, requestLootboxRng :1016 / index advance :1089/:1629, _resolveBuy :727-863, OPEN-E gate :343-352, funder :624, ARCH-04 reclaim sites :1553/:2113/:2676)
  - phase: 348-02 (CODE-SIZE-PLAN)
    provides: the MEASURED 24,358 B / 218 B headroom + the corrected ~1.4-1.7 KB clean reclaim + the running-total < 24,576 sequence (reclaim FIRST)
  - phase: 348-03 (FREEZE-PROOF)
    provides: FREEZE-02 the subsFullyProcessed no-interleave guard 349 must AUTHOR (ZERO source matches) + FREEZE-03 the stamped-day seed
  - phase: 348-03 (INVARIANT-CARRY)
    provides: the corrected no-valve invariant set (try/catch DROPPED, D-348-04) + EV-cap-at-open buy-time-write-bypassed + the slice-builder obligation-1
  - phase: 348-04 (PLACEMENT-DECISION)
    provides: the required-path STAGE mechanism (D-348-01 USER override) + the inherited mint-gate standing (ZERO new gate code)
provides:
  - 348-IMPL-EDIT-ORDER-MAP.md — the single producer-before-consumer edit-order for the 349 IMPL diff (reclaim FIRST -> DegenerusGameStorage append -> GameAfkingModule -> AdvanceModule STAGE insertion -> interfaces -> AfKing thin stubs), code-size-safe, with the four carried corrections threaded in
affects: [349-IMPL, 350-GAS, 351-TST, 352-TERMINAL]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Downstream-consumer edit-order map: a single doc reconciling all upstream SPEC deliverables into one producer-before-consumer IMPL diff sequence (the 343-IMPL-EDIT-ORDER-MAP.md precedent)"
    - "Code-size running-total carried into the edit-order so the runtime stays under the EIP-170 24,576-byte ceiling at every intermediate step (reclaim FIRST)"

key-files:
  created:
    - .planning/phases/348-spec-design-lock-freeze-proof-discharged-invariant-carry-4-p/348-IMPL-EDIT-ORDER-MAP.md
  modified: []

key-decisions:
  - "Used the MEASURED 24,358 B / 218 B headroom + the corrected ~1.4-1.7 KB clean reclaim from 348-02, NOT the v55 PLAN doc's overstated ~2.8 KB (R3's 953 B needs a 5-caller retarget; only R1 + the two thin wrappers are clean)"
  - "Sequenced the FREEZE-02 subsFullyProcessed no-interleave guard as something 349 AUTHORS (348-03 confirmed ZERO source matches), not an existing-code attestation"
  - "Carried the no-valve REVERT-02 (try/catch DROPPED, D-348-04) and the required-path STAGE placement (D-348-01) verbatim from the upstream docs; did NOT re-decide the 349-owned build"
  - "Reconciled the two open routes (afking-stamp + human openLootBox) as sharing no mutable-state hazard (shared EV-cap map = the intended one per-level budget, single RMW each; shared word map = write-once read-only)"

patterns-established:
  - "Pattern: every file:line in the consumer map is the ACTUAL re-pinned upstream anchor, never a doc-cited drifted line; the box seed is abi.encode (LB:534) not abi.encodePacked (LB:644 = PRESALE box)"
  - "Pattern: a re-pin-before-authoring caution closes every paper-only edit-order map — if contracts/ moves off the baseline before IMPL, re-run the attestation + re-derive the size running-total"

requirements-completed: [ARCH-04]

# Metrics
duration: 8min
completed: 2026-05-30
---

# Phase 348 Plan 05: Producer-Before-Consumer IMPL Edit-Order Map Summary

**348-IMPL-EDIT-ORDER-MAP.md fixes the single 349 IMPL diff sequence (code-size reclaim FIRST -> DegenerusGameStorage append -> GameAfkingModule -> AdvanceModule STAGE insertion -> interfaces -> AfKing thin stubs), carrying the MEASURED 24,358 B / 218 B headroom running-total < 24,576 and threading the four upstream corrections in.**

## Performance

- **Duration:** ~8 min
- **Started:** 2026-05-30T18:16:12Z
- **Completed:** 2026-05-30T18:23:52Z
- **Tasks:** 1
- **Files modified:** 1 (created)

## Accomplishments

- Authored `348-IMPL-EDIT-ORDER-MAP.md` (424 lines) — the DOWNSTREAM CONSUMER deliverable reconciling all five upstream 348 docs (348-01 attestation, 348-02 code-size, 348-03 freeze-proof + invariant-carry, 348-04 placement) into ONE producer-before-consumer edit-order for the 349 IMPL diff, mirroring the 343-IMPL-EDIT-ORDER-MAP.md format.
- **Section 1 — Final reconciled shapes:** the `DegenerusGameStorage` 2-slot layout-safe append (subscriber set `_subOf`/`_subscribers`/`_subscriberIndex` + the process/open cursors + `subsFullyProcessed` + the per-sub `(index, amount, day)` stamp + `lastAutoBoughtDay`/`lastOpenedIndex` markers + the REUSED v54 `afkingFunding` ledger, no new aggregate); the `GameAfkingModule` enumerated contents (subscribe/setters + process STAGE callee + open-pass + router — its bytecode is its OWN budget, 0 B to the Game); the TWO open routes (afking-stamp + human `openLootBox`) with the shared-no-mutable-state-hazard reconciliation; the `AfKing.sol` thin-dispatch-stub collapse (~8 stubs, ~1.0-1.5 KB Game-runtime).
- **Section 2 — Code-size running-total:** carried the MEASURED 24,358 B / 218 B headroom + the corrected ~1.4-1.7 KB clean reclaim (explicitly NOT the doc's overstated ~2.8 KB), with the worst-case (R1-low + stubs-high) running-total proven < 24,576 at every row (worst case lands at 24,418 after R1 + R2 + R3-wrapper).
- **Section 3 — The edit-order map:** an ordered 6-step table (reclaim FIRST -> storage append -> `GameAfkingModule` -> `AdvanceModule` STAGE insertion authoring the FREEZE-02 `subsFullyProcessed` no-interleave guard -> interfaces -> AfKing thin stubs) with a Producer/consumer-role + Code-size-running-total column, proving no downstream file ships an intermediate broken state and the Game never breaches 24,576 mid-flight.
- **Section 4 — Carried corrections threaded:** bound each upstream correction to its edit step — box-seed `abi.encode` re-pin -> open-pass; no-try/catch REVERT-02 (D-348-04) -> process/open STAGE; required-path override (D-348-01) -> AdvanceModule STAGE; EV-cap-at-open buy-time-write-bypassed -> open-pass.
- **Section 5 — Re-pin-before-authoring caution:** the 343 hand-off discipline — every anchor is a point-in-time snapshot of `20ca1f79`; if `contracts/` drifts before 349, re-run the attestation + re-derive the size running-total; the 349-owned design (BOX/REVERT/EVCAP/CONSENT/PLACE-02) is the BUILD this map SEQUENCES but does not re-decide.

## Task Commits

Each task was committed atomically:

1. **Task 1: Author 348-IMPL-EDIT-ORDER-MAP.md** - `3b7dc811` (docs)

**Plan metadata:** (this SUMMARY + STATE/ROADMAP/REQUIREMENTS) committed separately.

## Files Created/Modified

- `.planning/phases/348-spec-design-lock-freeze-proof-discharged-invariant-carry-4-p/348-IMPL-EDIT-ORDER-MAP.md` - the producer-before-consumer edit-order map for the single 349 batched diff, reconciling the GameAfkingModule + storage append + two-path open, code-size-safe, with the four carried corrections threaded in.

## Decisions Made

- **MEASURED figures over the PLAN doc's figures:** used 348-02's MEASURED 24,358 B / 218 B headroom and its corrected ~1.4-1.7 KB clean-reclaim (R1 `claimAffiliateDgnrs`->`BingoModule` is the only zero-caveat clean win; R3's 953 B requires a 5-caller retarget) rather than the v55 PLAN doc's overstated ~2.8 KB, per the plan's <important> directive.
- **FREEZE-02 guard as a 349-authored artifact:** sequenced `subsFullyProcessed` as something 349 AUTHORS (348-03 confirmed grep returns ZERO matches in the AdvanceModule today) with the no-interleave guard specified against the re-pinned `:1016`/`:1089`/`:1629`/`:274` lines, not assumed to exist.
- **Carried, not re-decided:** the no-valve REVERT-02 (D-348-04) and required-path STAGE placement (D-348-01) are carried verbatim from the upstream docs; the map sequences the 349-owned build (BOX/REVERT/EVCAP/CONSENT/PLACE-02) without re-litigating it.
- **Two-open-routes reconciliation:** recorded that the afking-stamp open and the human `openLootBox` route share no mutable-state hazard — the shared `lootboxEvBenefitUsedByLevel` map is the intended single per-level 10-ETH budget (one RMW each via `_applyEvMultiplierWithCap`, no double-draw, no revert), and the shared `lootboxRngWordByIndex` word map is write-once / read-only at open.

## Deviations from Plan

None - plan executed exactly as written. The single Task 1 was authored against the upstream docs' ACTUAL content (read in full, not just the plan's description of them), all acceptance criteria pass, and zero `contracts/*.sol` were modified.

## Issues Encountered

None. The five upstream producer docs and the 343 format precedent were all present and internally consistent; the only reconciliation needed was the one the plan flagged (use the MEASURED ~1.4-1.7 KB reclaim, not the doc's ~2.8 KB), which was applied.

## User Setup Required

None - paper-only SPEC deliverable; no external service configuration.

## Next Phase Readiness

- **349 IMPL is sequencing-complete from this map.** The author writes ONE fully-reconciled, code-size-safe `contracts/*.sol` diff against the actual re-pinned lines, with zero "by construction" assumptions and zero intermediate broken state — re-running the greps + the `forge build --sizes` measurement first if the tree has drifted off `20ca1f79`.
- This is the 5th of 6 plans in Phase 348. Plan 348-06 (the remaining wave) completes the SPEC phase per the ROADMAP.
- **Carry-forward for 349:** the GameAfkingModule + storage-append + two-path-open shapes are pre-reconciled; FREEZE-02's `subsFullyProcessed` guard is a 349-AUTHORED artifact; the no-valve REVERT-02 means obligation-1 (slice-builder fidelity, verbatim) is the SOLE no-brick guarantor; R1 reclaim MUST land before any stub addition.

## Self-Check: PASSED

- `348-IMPL-EDIT-ORDER-MAP.md` exists — FOUND.
- Commit `3b7dc811` exists in git log — FOUND.
- Plan automated verify (all 9 checks): file exists, "producer-before-consumer", "24576/24,576", "DegenerusGameStorage", "GameAfkingModule", "subsFullyProcessed", "abi.encode", re-pin caution, zero contracts edits — all PASS.

---
*Phase: 348-spec-design-lock-freeze-proof-discharged-invariant-carry-4-p*
*Completed: 2026-05-30*
