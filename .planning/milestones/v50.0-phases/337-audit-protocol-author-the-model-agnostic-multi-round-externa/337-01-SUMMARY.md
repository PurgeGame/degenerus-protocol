---
phase: 337-audit-protocol-author-the-model-agnostic-multi-round-externa
plan: 01
subsystem: audit
tags: [rng-audit-kit, vrf-freeze, anchor-attestation, context-pack, documentation, package-only, layout-b]

# Dependency graph
requires:
  - phase: 334-spec-design-lock-mintdiv-reachability-proof-rngaudit-structu
    provides: the locked R1->R4 sequence + the 4a-4e cold-start context-pack skeleton + the no-answer-key/package-only/model-agnostic framing
  - phase: 335-impl-the-one-batched-contract-diff
    provides: the frozen post-v50 contract surface (O(1) whalePassClaims, MintModule :720 realignment, AfKing pass-gating) the kit is authored against
provides:
  - "audit/rng-audit-kit/337-ANCHOR-ATTESTATION.md — fresh HEAD-resolved anchor table (A-G) for every contracts/ file:line the kit cites; 6 drift items flagged at NEW lines"
  - "audit/rng-audit-kit/RNG-AUDIT-KIT.md — cold-start context pack 4a-4e (locators only); reserved placeholder block for the 337-02 protocol head"
  - "The two-file Layout B scaffold under the new audit/rng-audit-kit/ directory (physically separate from audit/FINDINGS-*)"
affects: [337-02-freeze-invariant-target-and-R1-R4-protocol, 337-03-chunk-manifest-and-packaging, 337-04-anchor-resolution-lint]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Facts-not-verdicts cataloging: every context-pack entry is a neutral file:line locator; freeze conclusions are withheld (the answer key stays internal)"
    - "Storage-travels-with-every-chunk orientation: the delegatecall facade means writers/readers of one slot live in different module files; DegenerusGameStorage.sol is the shared anchor"
    - "Self-contained deliverable: zero reference to internal milestone reports or read-graph dumps; the kit stands alone on the attached source"

key-files:
  created:
    - audit/rng-audit-kit/337-ANCHOR-ATTESTATION.md
    - audit/rng-audit-kit/RNG-AUDIT-KIT.md
  modified: []

key-decisions:
  - "Recorded the actual authoring HEAD dc8f9ed4 (not the plan interface block's stale 03697dc4/f65fb0f1) — git diff e756a6f3 HEAD -- contracts/ is empty, so contracts are byte-frozen and every cited line resolves identically"
  - "Layout B confirmed: RNG-AUDIT-KIT.md (paste-into-model) + a separate CHUNK-MANIFEST.md (337-03), both under the NEW audit/rng-audit-kit/ dir for SC3 self-containment"
  - "Reserved an explicit HTML-comment placeholder block at the top of RNG-AUDIT-KIT.md for 337-02 to prepend the freeze-invariant target + exempt set + R1->R4 without a race"
  - "The MINTDIV pre-v50 heuristic survives ONLY as documentary text in the MintModule:718 comment; the executable advance is processed += take at :720 — cited the live :720, recorded the :716 line token as absent"

patterns-established:
  - "Pattern 1: Drift index up front — a 6-row table mapping each pre-v50 sketch line to its NEW HEAD line so later plans cannot copy a stale anchor"
  - "Pattern 2: No freeze-status column anywhere in the attestation; the single sentence mentioning 'freeze-status' explicitly asserts its ABSENCE (answer-key discipline)"

requirements-completed: [RNGAUDIT-03]

# Metrics
duration: 7min
completed: 2026-05-28
---

# Phase 337 Plan 01: RNG-Audit Kit Factual Foundation Summary

**Re-attested every kit anchor against frozen HEAD `dc8f9ed4` into a fresh drift-flagged table (337-ANCHOR-ATTESTATION.md), then authored the self-contained cold-start context pack 4a-4e (RNG-AUDIT-KIT.md) as neutral locators with all freeze verdicts withheld.**

## Performance

- **Duration:** ~7 min
- **Started:** 2026-05-28T19:47:37Z
- **Completed:** 2026-05-28T19:54:10Z
- **Tasks:** 2
- **Files modified:** 2 created

## Accomplishments
- Re-resolved all 50+ cited `contracts/` anchors with `grep`/`sed` against the frozen tree; confirmed the 6 v50-drifted anchors at their NEW lines (MintModule:720 `processed += take`, Lootbox:1253 `whalePassClaims[player] += 1`, `_applyWhalePassStats` 3->2 call sites, autoOpen:1695 / enqueue:1588 + `OPEN_NORMAL_GAS_UNIT` deleted, `lazyPassHorizon`:1540 NEW, whale-bonus constants deleted) and the UNCHANGED lock/VRF/consume machinery in AdvanceModule + Storage.
- Authored the cold-start context pack with all five exact headings (Context Pack 4a-4e), the verbatim write-time gate string, the 11-module inventory (correcting the stale "10 modules" framing), and the conditional cross-module tracing methodology — locators only.
- Established the two-file Layout B scaffold under the new `audit/rng-audit-kit/` directory, physically separate from `audit/FINDINGS-*`, with a reserved protocol-head placeholder for 337-02.

## Task Commits

Each task was committed atomically:

1. **Task 1: Re-attest every kit anchor against HEAD** - `dd9f0ea1` (docs)
2. **Task 2: Author the cold-start context pack 4a-4e** - `e25125c5` (docs)

**Plan metadata:** (this bookkeeping commit) (docs: complete plan)

## Files Created/Modified
- `audit/rng-audit-kit/337-ANCHOR-ATTESTATION.md` (153 lines) - Fresh HEAD-resolved attestation tables A-G + a 6-row drift index; the source of truth the 337-04 anchor-resolution lint checks against. No freeze-status column.
- `audit/rng-audit-kit/RNG-AUDIT-KIT.md` (137 lines) - The paste-into-model artifact: cold-start context pack sections 4a (module/RNG-window map), 4b (rngLock mechanics + verbatim write-gate), 4c (VRF entry/consume), 4d (11-module inventory + delegatecall-facade fact), 4e (cross-module variable-tracing methodology). Reserved placeholder block at top for the 337-02 protocol head.

## Decisions Made
- **Authoring HEAD recorded as the actual `dc8f9ed4`**, not the plan interface block's stale `03697dc4`/`f65fb0f1`. All three are equivalent under `contracts/` (the subject is byte-frozen vs the v50 IMPL `e756a6f3`), so anchors resolve identically; recording the true SHA keeps the attestation honest.
- **MINTDIV `:716` heuristic disposition:** the old `processed += writesUsed >> 1` text remains only as documentation in the comment at MintModule:718; the executable arithmetic is `processed += take` at :720. Cited the live :720 and confirmed the `:716` line token is absent (per the Task-1 lint).
- **Layout B + new dir** confirmed as the proposed default (no CONTEXT.md exists; the planner flagged these for the user gate). Both files live under `audit/rng-audit-kit/` for SC3 self-containment.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Reworded the attestation drift-index row to avoid a forbidden stale-line token**
- **Found during:** Task 1 (337-ANCHOR-ATTESTATION.md verification)
- **Issue:** When describing what the pre-v50 sketch said, the drift-index row literally wrote the string `OPEN_NORMAL_GAS_UNIT = 90_000`, which the Task-1 `<automated>` lint flags as a stale pre-v50 line (the lint forbids that exact literal). The verify chain returned FAIL on the negated clause even though every positive check passed.
- **Fix:** Reworded the row to "the `OPEN_NORMAL_GAS_UNIT` gas-weight carve-out constant" without reproducing the `= 90_000` literal value; meaning preserved, forbidden token removed.
- **Files modified:** audit/rng-audit-kit/337-ANCHOR-ATTESTATION.md
- **Verification:** Task-1 `<automated>` chain re-run -> PASS; the three forbidden tokens (`:716`, `1250-1260`, `OPEN_NORMAL_GAS_UNIT = 90_000`) all absent.
- **Committed in:** `dd9f0ea1` (Task 1 commit)

**2. [Rule 3 - Blocking] Reworded the kit's top discipline comment to avoid self-tripping the self-containment + no-answer-key lints**
- **Found during:** Task 2 (RNG-AUDIT-KIT.md verification)
- **Issue:** My own authoring-discipline comment at the top of the file literally listed the prohibited paths (`audit/FINDINGS-*.md`, `.planning/RNGLOCK-CATALOG.md`) and the prohibited verdict phrasings (`no escape`, `safe by construction`, `the invariant holds`, `we found/verified/confirmed`) in order to FORBID them. The greps cannot distinguish a prohibition from an actual reference/verdict, so the self-containment lint hit 1 and the no-answer-key lint hit 2.
- **Fix:** Reworded the discipline comment to convey the same SHIP/WITHHOLD rules without reproducing any forbidden literal token or path (e.g. "Carry no pointer to any internal milestone report or internal read-graph dump"; "WITHHOLD every freeze conclusion about any specific slot").
- **Files modified:** audit/rng-audit-kit/RNG-AUDIT-KIT.md
- **Verification:** Task-2 `<automated>` -> PASS; self-containment grep = 0, no-answer-key grep = 0, broader skeptic sweep = 0; body unaffected (5 headings, verbatim write-gate, MintStreakUtils all still present).
- **Committed in:** `e25125c5` (Task 2 commit)

---

**Total deviations:** 2 auto-fixed (both Rule 3 - blocking lint self-trips from documentation prose).
**Impact on plan:** Both were authored-text adjustments to satisfy the plan's own grep gates; zero change to the substantive locator content, zero scope creep, zero `contracts/` impact.

## Issues Encountered
- The literal-string lints are intentionally blunt (they cannot tell a prohibition from a reference). Lesson for 337-02/03: describe forbidden tokens/paths by paraphrase, never by reproducing the literal, even inside comments or instructions.

## User Setup Required
None - documentation-only deliverable, no external service configuration, no package installs (RESEARCH "Standard Stack" = Not applicable).

## Next Phase Readiness
- **337-02** can prepend the freeze-invariant target (RNGAUDIT-01) + exempt-entry set + R1->R4 protocol into the reserved placeholder block at the top of `RNG-AUDIT-KIT.md`; all anchors it needs are in `337-ANCHOR-ATTESTATION.md`.
- **337-03** can author `CHUNK-MANIFEST.md` referencing the 4d inventory + the per-file sizes from RESEARCH §5.
- **337-04** anchor-resolution lint has its source-of-truth table (the attestation) to enforce against HEAD.
- No blockers. `contracts/*.sol` untouched (verified `git diff --name-only HEAD -- contracts/` empty).

## Self-Check: PASSED

- FOUND: audit/rng-audit-kit/337-ANCHOR-ATTESTATION.md
- FOUND: audit/rng-audit-kit/RNG-AUDIT-KIT.md
- FOUND: .planning/phases/337-audit-protocol-author-the-model-agnostic-multi-round-externa/337-01-SUMMARY.md
- FOUND commit: dd9f0ea1 (Task 1)
- FOUND commit: e25125c5 (Task 2)

---
*Phase: 337-audit-protocol-author-the-model-agnostic-multi-round-externa*
*Completed: 2026-05-28*
