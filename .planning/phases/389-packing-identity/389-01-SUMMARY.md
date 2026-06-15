---
phase: 389-packing-identity
plan: 01
subsystem: testing
tags: [audit, cross-model-council, gemini, codex, storage-packing, gas-identity, byte-freeze]

# Dependency graph
requires:
  - phase: 388-foundation-subject-freeze-green-baseline
    provides: "byte-frozen subject a8b702a7, the FC-389-01..09 finding-candidate intake ledger, and the authoritative 388-01 storage LAYOUT-KEY"
provides:
  - "NET 1 (cross-model council) ON RECORD for the STORAGE-01..07 + GASID-01..05 packing-identity surface"
  - "Two neutral council prompts (STORAGE + GASID) charged against frozen a8b702a7"
  - "Raw gemini + codex output per slice (4 files) + council.json manifests"
  - "389-01-COUNCIL-NET.md capture record with byte-freeze attestation and the raw leads/divergences for 389-02 to fold in"
affects: [389-02-adjudication, packing-identity-verdict, both-nets-on-record-gate]

# Tech tracking
tech-stack:
  added: []
  patterns: ["dual-net audit: NET 1 council fan-out captured raw before the Claude net + adjudication (389-02)"]

key-files:
  created:
    - .planning/phases/389-packing-identity/389-01-COUNCIL-PROMPT-STORAGE.md
    - .planning/phases/389-packing-identity/389-01-COUNCIL-PROMPT-GASID.md
    - .planning/phases/389-packing-identity/council/storage.gemini.txt
    - .planning/phases/389-packing-identity/council/storage.codex.txt
    - .planning/phases/389-packing-identity/council/gasid.gemini.txt
    - .planning/phases/389-packing-identity/council/gasid.codex.txt
    - .planning/phases/389-packing-identity/council/storage.council.json
    - .planning/phases/389-packing-identity/council/gasid.council.json
    - .planning/phases/389-packing-identity/389-01-COUNCIL-NET.md
  modified: []

key-decisions:
  - "Ran both council slices serially (STORAGE then GASID) per the pacing rule, not parallel"
  - "Captured raw council output verbatim without adjudication — adjudication is 389-02's job"
  - "Routed the codex-surfaced STORAGE-06 stale-harness leads + the FC-389-03 raw/effective model divergence forward as raw leads for 389-02 (not refuted here)"

patterns-established:
  - "Pattern: a no-finding sweep verdict requires BOTH nets on record; NET 1 council captured first, RAW, then 389-02 folds it against the Claude net"

requirements-completed: [STORAGE-01, STORAGE-02, STORAGE-03, STORAGE-04, STORAGE-05, STORAGE-06, STORAGE-07, GASID-01, GASID-02, GASID-03, GASID-04, GASID-05]

# Metrics
duration: 35min
completed: 2026-06-15
---

# Phase 389 Plan 01: PACKING-IDENTITY NET 1 (Cross-Model Council) Summary

**NET 1 (gemini + codex) on record for the STORAGE-01..07 + GASID-01..05 packing-identity surface against byte-frozen `a8b702a7` — 0 CLIs skipped, both slices fanned, raw output captured, subject byte-frozen throughout.**

## Performance

- **Duration:** ~35 min
- **Started:** 2026-06-14T23:52Z
- **Completed:** 2026-06-15T00:27Z
- **Tasks:** 2
- **Files created:** 11 (.planning/ only; no contract source touched)

## Accomplishments
- Authored two neutral council prompts ("here is what we believe is safe — find where it breaks"), each instructing the council to read the EXACT frozen source at `a8b702a7` via `git show`, carrying the threat-priority line, the KNOWN-BY-DESIGN exclusion list, and the per-finding output format. STORAGE covers STORAGE-01..07 + FC-389-01..04 (FA-1 two-window eviction as the prime target); GASID covers GASID-01..05 + FC-389-05..09.
- Ran `council.sh` for both `--label storage` and `--label gasid` serially. Both `gemini` and `codex` were available on BOTH slices — `skipped[]` empty for both — so all four model outputs were captured.
- Both models returned substantive, source-traced output. The aggregate council verdict on this slice is **no production packing/identity defect**: every STORAGE/GASID thesis point and FC-389-* lead returned SOUND/IDENTICAL except the codex STORAGE-06 stale-harness leads (LOW / oracle-integrity, not contract defects) and the FC-389-03 comment-framing divergence — both routed forward as RAW leads.
- Verified the subject byte-frozen after the fan-out (`git diff a8b702a7 -- contracts/` and `git status --porcelain contracts/` both empty) and recorded the attestation + "NET 1 ON RECORD" in 389-01-COUNCIL-NET.md.

## Task Commits

1. **Task 1: Author the two neutral council prompts (STORAGE + GASID)** - `4c4043ca` (docs)
2. **Task 2: Run the council fan-out (both slices) and record the council-net capture** - `32556a05` (docs)

## Files Created/Modified
- `389-01-COUNCIL-PROMPT-STORAGE.md` - Neutral STORAGE-01..07 + FC-389-01..04 council prompt (116 lines)
- `389-01-COUNCIL-PROMPT-GASID.md` - Neutral GASID-01..05 + FC-389-05..09 council prompt (113 lines)
- `council/storage.gemini.txt`, `council/storage.codex.txt` - Raw STORAGE-slice council output
- `council/gasid.gemini.txt`, `council/gasid.codex.txt` - Raw GASID-slice council output
- `council/storage.council.json`, `council/gasid.council.json` - Manifests (both: models [gemini, codex], skipped [])
- `council/*.err` - Per-model stderr (both models exited 0 on both slices)
- `389-01-COUNCIL-NET.md` - Capture record: available/skipped per slice, raw output paths, per-model one-line characterizations, the raw leads/divergences for 389-02, and the byte-freeze attestation (121 lines)

## Decisions Made
- Ran the two slices serially per `[[pace-runs-to-survive-5h-cap]]`, not parallel across council invocations.
- Captured council output verbatim and did NOT adjudicate — per the plan, 389-02 (Claude net + adjudication) owns the verdict. The COUNCIL-NET record flags the two items needing 389-02 attention (the codex STORAGE-06 harness leads vs the 388-01 reconciled poke set; the FC-389-03 raw-vs-effective model divergence) as RAW leads.

## Deviations from Plan

None - plan executed exactly as written. Both tasks completed, both verification gates passed, no contract source touched, no auto-fix rules triggered.

## Council leads routed to 389-02 (RAW — for adjudication, not refuted here)
1. **STORAGE-06 stale-harness leads (codex).** 3 additional slot-hardcoded harnesses codex flagged as possibly poking a MOVED field (`Composition`/`CompositionHandler` slot-10 `mintPacked_` vs `rngWordByDay`; `SweepWorstCaseDrain` + `RngLockDeterminism` box-cursor slots 58/59; `HeroOverride*.test.js` lootboxRng slot 35 vs 34). These are outside the 388-01 LAYOUT-KEY §6 reconciled poke set → 389-02 must check each against `forge inspect`. LOW / oracle-integrity (not a contract defect) if confirmed.
2. **FC-389-03 model divergence.** Both council models assert `DecClaimRound.totalBurn` stores EFFECTIVE (not raw) burns — contradicting the storage-map FA-3 framing — but disagree on which comment (`DecClaimRound.totalBurn` vs `DecEntry.burn`) is imprecise. 389-02 must re-read the Decimator accumulator path to settle it. All three lenses agree the uint128 bound is sound regardless (INFO comment-accuracy, not overflow).
3. All other FC-389-* leads + thesis points returned SOUND/IDENTICAL by both models with source traces — 389-02 confirms against the Claude net for both-nets-on-record on those items.

## Issues Encountered
None. Both CLIs were available; the `council.sh` background runs completed cleanly (exit 0), monitored to completion via the council.json sentinel.

## User Setup Required
None - no external service configuration required (the gemini/codex CLIs were already authenticated at `~/.local/bin`).

## Next Phase Readiness
- NET 1 is on record for the full STORAGE + GASID packing-identity surface. 389-02 (the Claude net + adjudication) can now fold the council leads in before issuing any per-item verdict, and confirm both-nets-on-record before a no-finding verdict.
- Subject remains byte-frozen at `a8b702a7`; no blockers.

## Self-Check: PASSED

- All 11 created files verified present on disk.
- Both task commits (`4c4043ca`, `32556a05`) verified in git log.
- `git diff a8b702a7 -- contracts/` empty (subject byte-frozen).

---
*Phase: 389-packing-identity*
*Completed: 2026-06-15*
