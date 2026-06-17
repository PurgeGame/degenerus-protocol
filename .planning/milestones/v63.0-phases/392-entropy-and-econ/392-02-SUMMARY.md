---
phase: 392-entropy-and-econ
plan: 02
subsystem: testing
tags: [audit, cross-model-council, burnie, coinflip, redemption-backing, seed-stake, gemini, codex]

# Dependency graph
requires:
  - phase: 388-foundation-subject-freeze-green-baseline
    provides: byte-frozen subject a8b702a7 + the routed finding-candidate ledger (FC-392-16..20, FC-392-11/-12/-13)
  - phase: 391-rng-spine
    provides: the FC-392-11 RNG-lock half attested airtight (the backing-dynamics half owned here)
provides:
  - NET 1 (cross-model council) ON RECORD for the BURNIE/coinflip-rework slice (BURNIE-01..06 + FC-392-16..20 + cross-ref FC-392-11/-12/-13)
  - the neutral BURNIE council prompt charged against frozen a8b702a7 (two prime backing leads charged hard)
  - raw gemini output + the codex-skip record + the council.json manifest
  - 392-02-COUNCIL-NET.md capture record with the byte-freeze attestation + NET 1 ON RECORD line + the RAW leads routed to 392-04
affects: [392-04, 396]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Cross-model council fan-out via council.sh --label NAME (gemini + codex, detect-and-skip)"
    - "Two prime leads charged HARD as dedicated CONFIRM/REFUTE/BY-DESIGN numbered break-targets demanding the accounting traced, not a hand-wave"

key-files:
  created:
    - .planning/phases/392-entropy-and-econ/392-02-COUNCIL-PROMPT-BURNIE.md
    - .planning/phases/392-entropy-and-econ/392-02-COUNCIL-NET.md
    - .planning/phases/392-entropy-and-econ/council/burnie.gemini.txt
    - .planning/phases/392-entropy-and-econ/council/burnie.council.json
  modified: []

key-decisions:
  - "codex skipped (hard usage-limit cap, same as 392-01) is recorded faithfully in skipped[]; a single available model (gemini) with real content satisfies 'council on record' with the skip documented (both-unavailable does NOT apply)"
  - "gemini's two prime FINDINGS (carry stranded BURNIE-04/FC-392-16 + VAULT window-aging BURNIE-05/FC-392-17) are RAW leads routed to 392-04 for the skeptic dual-gate + design-intent disposition — NOT adjudicated here"

patterns-established:
  - "RAW capture only — the council finds, Claude adjudicates at the Wave-2 plan (392-04); no verdict pre-stated"

requirements-completed: [BURNIE-01, BURNIE-02, BURNIE-03, BURNIE-04, BURNIE-05, BURNIE-06]

# Metrics
duration: ~30min
completed: 2026-06-14
---

# Phase 392 Plan 02: BURNIE/Coinflip-Rework Council Net (NET 1) Summary

**NET 1 (cross-model council) ON RECORD for the BURNIE/coinflip-seeded-emission rework — gemini CONFIRMS both prime backing leads as FINDINGS (auto-rebuy carry stranded from sDGNRS redemption backing + VAULT seed 30-day window-aging forfeiture) and VERIFIES SOUND on survive-before-mint, emission conservation, latch monotonicity, and packed-lane losslessness; codex skipped (usage-limit cap), all RAW leads routed to 392-04.**

## Performance

- **Duration:** ~30 min
- **Started:** 2026-06-14T22:10:00Z (approx)
- **Completed:** 2026-06-14T22:40:00Z (approx)
- **Tasks:** 2
- **Files modified:** 6 created (2 docs + 4 council artifacts)

## Accomplishments
- Authored the neutral BURNIE/coinflip-rework council prompt (307 lines) against frozen `a8b702a7`, covering all 6 BURNIE reqs + the 5 owned coinflip-burnie leads (FC-392-16..20) + the 3 cross-ref backing-dynamics leads (FC-392-11/-12/-13), with the two prime backing leads (FC-392-16 carry-excluded-from-backing, FC-392-17 VAULT seed window-aging) charged HARD as dedicated CONFIRM/REFUTE/BY-DESIGN targets demanding the backing accounting traced — encoding the survive-before-mint defining intent + the intended-variance-trade anchor + the BURNIE-off-the-ETH-spine framing + the KNOWN-BY-DESIGN exclusion list.
- Ran the council fan-out (`council.sh --label burnie`): gemini ON RECORD with a substantive 41-line traced audit; codex SKIPPED (hard usage-limit cap, faithfully recorded in `skipped[]`).
- gemini CONVERGED on BOTH prime targets as FINDINGS — PRIME-01 (carry stranded from redemption backing) and PRIME-02 (VAULT seed window-aging forfeiture) — and VERIFIED SOUND on BURNIE-01/02/03/06.
- Captured the council-net record (`392-02-COUNCIL-NET.md`) with the manifest, raw-output paths, per-model characterization, the byte-freeze attestation, the NET 1 ON RECORD line, and the RAW leads routed to 392-04 (no adjudication here).
- Verified the subject byte-frozen throughout (`git diff a8b702a7 -- contracts/` empty; no stray files — gemini's claimed `BURNIE-AUDIT-REPORT.md` write was blocked by read-only mode and never landed anywhere).

## Task Commits

Each task was committed atomically:

1. **Task 1: Author the neutral BURNIE/coinflip council prompt** - `e2bb1c9c` (docs)
2. **Task 2: Run the BURNIE council fan-out + record the council-net capture** - `785d7d8d` (docs)

**Plan metadata:** (this commit) (docs: complete plan)

## Files Created/Modified
- `.planning/phases/392-entropy-and-econ/392-02-COUNCIL-PROMPT-BURNIE.md` - the neutral council prompt (307 lines) for the BURNIE slice + the prime + cross-ref leads
- `.planning/phases/392-entropy-and-econ/392-02-COUNCIL-NET.md` - the NET 1 capture record (manifest, characterization, byte-freeze attestation, routed leads)
- `.planning/phases/392-entropy-and-econ/council/burnie.gemini.txt` - gemini's raw 41-line traced audit (RAW, not adjudicated)
- `.planning/phases/392-entropy-and-econ/council/burnie.council.json` - the council manifest (available: gemini; skipped: codex)
- `.planning/phases/392-entropy-and-econ/council/burnie.gemini.err` - gemini stderr (0 bytes, clean exit)
- `.planning/phases/392-entropy-and-econ/council/burnie.codex.err` - the codex wrapper skip notice

## Decisions Made
- **codex skip is not a failure.** codex hit the same hard usage-limit cap as in 392-01 (resets ~11:56 PM). Per the plan's both-unavailable rule, a single available model (gemini) with real content satisfies "council on record" with the skip documented; the both-unavailable re-run condition does NOT apply. The codex skip is carried to 392-04/396 for an opportunistic post-reset re-run to second-source the prime findings + cover the non-prime leads gemini did not explicitly characterize.
- **RAW capture only.** gemini's two FINDINGS land exactly on the two prime targets but are RAW property-break leads — 392-04 adjudicates them with the skeptic dual-gate + the design-intent disposition (the intended variance trade + BURNIE "worthless except the whale pass" bounds severity to an under-credit/strand or lost-emission class, NOT an ETH insolvency, but a confirmed under-credit/lost-emission window is still a value-bearing finding). No verdict pre-stated here.

## Deviations from Plan

None - plan executed exactly as written.

## Known Stubs

None - this is an audit-only documentation slice; no contract or application code was created or modified.

## Issues Encountered
- **codex usage-limit cap (anticipated).** codex skipped on the hard usage-limit cap (identical banner to 392-01). The phase guardrails anticipated this; recorded faithfully in `skipped[]` and the NET record. gemini + the upcoming Claude net (392-04) still satisfy the dual-NET requirement.
- **gemini claimed-but-not-written report (anticipated pattern).** gemini's narrative claims it "saved the report to `BURNIE-AUDIT-REPORT.md`", but `--approval-mode plan` (read-only) blocked the write; `find` confirms no such file exists anywhere and no file outside `council/` was touched. Same claimed-but-not-written pattern as 392-01. Subject byte-frozen; no stray file to remove.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- NET 1 is on record for the BURNIE slice; both prime FINDINGS + the SOUND attestations + the carried non-prime leads are documented for 392-04 (NET 2 Claude + adjudication BURNIE slice).
- 392-04 must: re-read the frozen source and adjudicate BURNIE-01..06 + FC-392-16..20 + FC-392-11/-12/-13; apply the dedicated EXHAUSTIVE carry-backing trace (FC-392-16) + the VAULT-window determination (FC-392-17) with the skeptic gate + a design-intent-vs-defect disposition; re-verify emission conservation (BurnieEmissionSeeds 5/5) + survive-before-mint enumeration + latch-monotonicity + packed-lane round-trip + the loss-sequence backing model; and consolidate both slices' findings.
- Recommended at 392-04/396: opportunistic codex re-run post-limit-reset to second-source the two prime FINDINGS and the non-prime leads.

## Self-Check: PASSED

---
*Phase: 392-entropy-and-econ*
*Completed: 2026-06-14*
