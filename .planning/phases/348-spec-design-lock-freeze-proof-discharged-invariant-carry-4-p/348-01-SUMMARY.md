---
phase: 348-spec-design-lock-freeze-proof-discharged-invariant-carry-4-p
plan: 01
subsystem: audit
tags: [grep-attestation, call-graph, freeze-invariant, drift-correction, afking-in-game, v55]

# Dependency graph
requires:
  - phase: v54.0 (343 SPEC + 344 IMPL, HEAD 20ca1f79)
    provides: the byte-identical contracts/ baseline the attestation greps against
provides:
  - 348-GREP-ATTESTATION.md — the call-graph attestation + per-file Drift-Correction Tables re-pinning EVERY v55 milestone-scope anchor to its ACTUAL current line vs 20ca1f79, with matched source text quoted
  - RESOLVED box-seed pattern-drift (openLootBox seed at LootboxModule:534 is keccak256(abi.encode(...)), NOT abi.encodePacked; abi.encodePacked is the PRESALE box at :644)
  - RE-PINNED OPEN-E subscribe gate (AfKing.sol:343-352, doc-cited :400-409) + src/funder resolution (:624, doc-cited :682) + _resolveBuy body extent (:727-863, doc-cited to :795)
  - FREEZE-03 entropy-side confirmation (ZERO block.* in DegenerusGameLootboxModule.sol)
affects: [348-03 FREEZE-PROOF, 348 PLACEMENT-DECISION, 348 INVARIANT-CARRY, 348-02 CODE-SIZE-PLAN, 348 GAS-INVENTORY, 348 IMPL-EDIT-ORDER-MAP, 349 IMPL]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Drift-Correction Table — Symbol | Doc-cited | Actual | Matched source text (quoted) | Status (MATCH/DRIFT/PATTERN-DRIFT/FOUND)"
    - "Empty-diff baseline identity — git diff --numstat 20ca1f79 HEAD -- contracts/ empty ⟹ grep on the live tree IS attestation against 20ca1f79 (no checkout)"

key-files:
  created:
    - .planning/phases/348-spec-design-lock-freeze-proof-discharged-invariant-carry-4-p/348-GREP-ATTESTATION.md
  modified: []

key-decisions:
  - "Box-seed pattern-drift RESOLVED: openLootBox seed at :534 is abi.encode (line correct, cited grep-pattern abi.encodePacked was wrong); abi.encodePacked is the ONLY-other-seed PRESALE box at :644 — FREEZE-03 proof must cite abi.encode"
  - "OPEN-E subscribe gate re-pinned :343-352 (was :400-409); src/funder resolution re-pinned :624 (was :682); _resolveBuy body extent re-pinned :727-863 (was to :795) — all other anchors MATCH"
  - "FREEZE-03 entropy-side confirmed clean: ZERO block.timestamp/number/prevrandao/coinbase/blockhash in the LootboxModule draw at :534 and the whole file"

patterns-established:
  - "No 'by construction' / 'single fn reaches all paths' claim survives un-checked (feedback_verify_call_graph_against_source floor) — every v55 PLAN-doc file:line re-grepped vs the live tree before it propagates into any 348 proof/decision doc or the 349 IMPL"

requirements-completed: [FREEZE-02, FREEZE-03, ARCH-04]

# Metrics
duration: 18min
completed: 2026-05-30
---

# Phase 348 Plan 01: Call-Graph Grep-Attestation + Drift-Correction Table Summary

**Re-pinned EVERY v55 milestone-scope `file:line` to its ACTUAL line vs the v54 HEAD `20ca1f79` (byte-identical working tree) with matched source text quoted — RESOLVING the box-seed pattern-drift (`abi.encode` at `:534`, `abi.encodePacked` = PRESALE box `:644`), re-pinning the OPEN-E gate (`:343-352`) / `src` resolution (`:624`) / `_resolveBuy` extent (`:727-863`), and confirming ZERO `block.*` entropy in the lootbox draw.**

## Performance

- **Duration:** 18 min
- **Started:** 2026-05-30T17:30:03Z
- **Completed:** 2026-05-30
- **Tasks:** 1
- **Files modified:** 1 (created)

## Accomplishments
- Recorded the empty-diff baseline identity: `git diff --numstat 20ca1f79 HEAD -- contracts/` is EMPTY (9 docs-only commits since), so grep on the live working tree IS a valid attestation against `20ca1f79` — no checkout needed.
- **RESOLVED the one confirmed drift** CONTEXT.md flagged: the `openLootBox` box seed at `DegenerusGameLootboxModule.sol:534` is `keccak256(abi.encode(rngWord, player, day, amount))` — the `abi.encode` form. The line `:534` is CORRECT; only the cited grep-*pattern* (`abi.encodePacked`) was wrong. `abi.encodePacked` appears at exactly ONE site — `:644`, the PRESALE box. FREEZE-03's "seed = keccak256(rngWord, player, day, amount)" is TRUE at `:534` but the proof must cite `abi.encode`.
- Re-pinned three additional drifts: the OPEN-E subscribe-time `fundingSource` gate `:343-352` (doc-cited `:400-409`), the `src`/funder resolution `:624` (doc-cited `:682`), and the `_resolveBuy` body extent `:727-863` (doc-cited "to :795").
- Confirmed every FREEZE-02 / FREEZE-03 / EV-cap / slice-builder / OPEN-E / ARCH-04 anchor with matched source text, and that there is ZERO `block.timestamp/number/prevrandao/coinbase/blockhash` in the LootboxModule draw (FREEZE-03 entropy-side).
- Ended with the no-"by-construction"-survives-unchecked attestation + a "Valid until" note (re-run if the subject HEAD's `contracts/` moves before 349).

## Task Commits

Each task was committed atomically:

1. **Task 1: Record the empty-diff baseline identity + author the per-file Drift-Correction Table vs 20ca1f79** - `bd4e031e` (docs)

**Plan metadata:** `5661d341` (docs: complete plan — STATE.md + ROADMAP.md tracking updates)

## Files Created/Modified
- `.planning/phases/348-spec-design-lock-freeze-proof-discharged-invariant-carry-4-p/348-GREP-ATTESTATION.md` - The call-graph attestation + per-file Drift-Correction Tables (LootboxModule / Storage / AfKing / AdvanceModule / DegenerusGame) re-pinning every v55 milestone-scope anchor vs `20ca1f79` with matched text, the box-seed drift resolution, the FREEZE-03 entropy-side guard, and the no-"by-construction" attestation.

## Decisions Made
- **Box-seed drift resolution recorded as PATTERN-DRIFT (not line drift):** the line `:534` is correct; the cited grep-pattern was wrong (`abi.encode` vs `abi.encodePacked`). Documented why the encoding difference is load-bearing (different hash preimages → a copied `abi.encodePacked` would compute a different seed and break box-outcome equivalence with `openLootBox`).
- **Attestation scope held to the `<canonical_refs>` anchor list:** the proof's `batchPurchase`/`purchaseWith`/`_processMintPayment` revert-primitive call-graph is attested in `PLAN-V55-REVERT-FREE-CHAIN-PROOF.md` itself; this doc additionally re-confirmed the `Storage:841/843/847` shortfall-settle anchors that the proof's class-A discharge + class-B residual both lean on (they sit in the v55 freeze/solvency spine).
- **ARCH-04 targets PINNED only, not measured:** per D-348-08 the byte measurement + running-total edit-order arithmetic are 348-02's CODE-SIZE-PLAN; this plan confirms the three reclaim-target function defs exist at their actual lines (`:1553`/`:2113`/`:2676`, all MATCH).

## Deviations from Plan

None - plan executed exactly as written. (The three line-number re-pins and the box-seed pattern-drift resolution are the plan's explicit purpose — drift correction is the deliverable, not a deviation from it. No contract or test files were touched; the pre-existing unrelated `scope.txt` change was left untouched.)

## Issues Encountered
None. Every doc-cited anchor was located on the live tree; the four drifts (box-seed pattern, OPEN-E gate line, `src` resolution line, `_resolveBuy` body extent) were the expected drift-correction work and are documented in §1 of the attestation.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- The attestation is the UPSTREAM PRODUCER for the rest of Phase 348 (the FREEZE-PROOF, PLACEMENT-DECISION, INVARIANT-CARRY, CODE-SIZE-PLAN, GAS-INVENTORY, IMPL-EDIT-ORDER-MAP) and the 349 IMPL diff — all of which must now cite the ACTUAL lines in §1–§2, not the drifted doc lines.
- Load-bearing handoffs: open seed = `keccak256(abi.encode(rngWord, player, day, amount))` at `:534`; frozen buy-day template = `lootboxDay[index][player]` at `:514`; OPEN-E gate = `:343-352`; funder resolution = `:624`; FREEZE-02 index advance = `:1089` AND `:1629`; STAGE insertion point = immediately before the `rngGate(` call at `AdvanceModule:274`.
- Valid until the subject HEAD's `contracts/` moves off `20ca1f79`; re-run before 349 if any `contracts/*.sol` commit lands.

## Self-Check: PASSED

- 348-GREP-ATTESTATION.md exists (created).
- Plan Task-1 automated verify gate: PASS (all required strings present; `git diff --name-only -- contracts/` empty).
- Zero `contracts/*.sol` edits.

---
*Phase: 348-spec-design-lock-freeze-proof-discharged-invariant-carry-4-p*
*Completed: 2026-05-30*
