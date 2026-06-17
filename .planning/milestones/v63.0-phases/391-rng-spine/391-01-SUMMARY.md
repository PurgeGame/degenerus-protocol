---
phase: 391-rng-spine
plan: 01
subsystem: audit
tags: [rng-freeze, vrf, council, cross-model, decimator-uint32, backward-trace, audit-only]

# Dependency graph
requires:
  - phase: 388-foundation-subject-freeze-green-baseline
    provides: byte-frozen subject a8b702a7 + FC-391-01..05 finding-candidate ledger + the decimator-uint32 MISSING-distribution oracle hole routed to RNG-02
  - phase: 390-solvency-spine
    provides: the proven NET-1 council-prompt + COUNCIL-NET capture shape (DOMINANT-class slice framing)
provides:
  - NET 1 (cross-model council) on record for the full RNG-FREEZE spine (RNG-01..06)
  - the neutral RNG-freeze council prompt (391-01-COUNCIL-PROMPT-RNG.md) charged against frozen a8b702a7
  - raw gemini + codex traced output (0 skipped) under council/
  - the council-net capture record (391-01-COUNCIL-NET.md) with the cross-model divergence routed to 391-02
affects: [391-02 (NET 2 Claude + adjudication), 396 TERMINAL (both-nets-on-record consolidation)]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Dual-net audit: NET 1 (council) on record FIRST so Wave-2 Claude-net + adjudication can fold the leads in before any verdict"
    - "Neutral charge of a DOMINANT-class slice: KNOWN-BY-DESIGN exclusion list + backward-trace doctrine + in-window SLOAD enumeration, no pre-stated verdict"

key-files:
  created:
    - .planning/phases/391-rng-spine/391-01-COUNCIL-PROMPT-RNG.md
    - .planning/phases/391-rng-spine/council/rng.gemini.txt
    - .planning/phases/391-rng-spine/council/rng.codex.txt
    - .planning/phases/391-rng-spine/council/rng.council.json
    - .planning/phases/391-rng-spine/391-01-COUNCIL-NET.md
  modified: []

key-decisions:
  - "Left RNG-01..06 UNMARKED — NET 1 on record does not issue a per-item verdict; the no-finding/finding verdict needs BOTH nets on record (issued at 391-02 adjudication)"
  - "Charged the decimator uint32 distribution-bias prime (RNG-02/FC-391-04) as a dedicated break-target demanding a real distribution argument, not a hand-wave — both models complied with a keccak-diffusion / per-address random-oracle argument"
  - "Recorded the codex cross-round uint32 seed-collision lead (RNG-04) faithfully as a RAW divergence vs gemini's SOUND — routed to 391-02, not adjudicated here"

patterns-established:
  - "RNG council prompt: north-star freeze doctrine (commitment-before-word + no live post-reveal input + in-window SLOAD enumeration + one-shot) as the thesis to break, mapped to the req IDs"

requirements-completed: []

# Metrics
duration: ~13min
completed: 2026-06-15
---

# Phase 391 Plan 01: RNG-SPINE NET 1 (Cross-Model Council) Summary

**NET 1 (gemini + codex) on record for the full RNG-FREEZE spine against frozen `a8b702a7`: both models VERIFIED SOUND on RNG-01/02/03/05/06 with backward-traced commitment points and a real decimator-distribution argument; codex surfaced one INFO/LOW cross-round `uint32` claim-seed collision (RNG-04) that gemini ruled sound — the single divergence, routed raw to 391-02.**

## Performance

- **Duration:** ~13 min (council fan-out ~9 min of it)
- **Started:** 2026-06-15 (Phase 391 execution start)
- **Completed:** 2026-06-15
- **Tasks:** 2
- **Files modified:** 6 created (1 prompt + 3 council outputs + 2 err stubs + 1 net record; 0 contract source)

## Accomplishments

- Authored the neutral RNG-FREEZE council prompt (296 lines) charged against the byte-frozen subject `a8b702a7`, covering RNG-01..06 + FC-391-01..05 owned leads + the inherited cross-refs FC-389-05 and FC-392-11, with the decimator uint32 distribution-bias prime (RNG-02/FC-391-04) charged HARD as a dedicated break-target and the backward-trace + in-window-SLOAD doctrine + KNOWN-BY-DESIGN exclusion list encoded — no verdict pre-stated.
- Ran the council fan-out (`council.sh --label rng`) to gemini + codex in parallel; both available, 0 skipped, both exited 0 (err files 0 bytes).
- Captured raw model output + the council.json manifest under the phase `council/` dir and wrote the council-net capture record (391-01-COUNCIL-NET.md, 161 lines) with the cross-model divergence + the prime-target convergent-SOUND attestation routed to 391-02.
- Verified the subject byte-frozen throughout (`git diff a8b702a7 -- contracts/` empty; `git status --porcelain contracts/` empty after the fan-out).

## Task Commits

Each task was committed atomically:

1. **Task 1: Author the neutral council prompt for the RNG-FREEZE slice** - `bb0c85bc` (docs)
2. **Task 2: Run the council fan-out and record the council-net capture** - `61b55436` (docs)

**Plan metadata:** (this SUMMARY + STATE.md + ROADMAP.md) - final docs commit

## Files Created/Modified

- `.planning/phases/391-rng-spine/391-01-COUNCIL-PROMPT-RNG.md` - the neutral RNG-freeze council prompt (the thesis to break, mapped to RNG-01..06)
- `.planning/phases/391-rng-spine/council/rng.gemini.txt` - gemini raw traced output (VERIFIED SOUND all RNG-01..06, 0 findings)
- `.planning/phases/391-rng-spine/council/rng.codex.txt` - codex raw traced output (1 INFO/LOW RNG-04 cross-round collision + SOUND elsewhere)
- `.planning/phases/391-rng-spine/council/rng.council.json` - the manifest (models: gemini+codex; skipped: empty)
- `.planning/phases/391-rng-spine/council/rng.gemini.err` / `rng.codex.err` - per-model stderr (both 0 bytes)
- `.planning/phases/391-rng-spine/391-01-COUNCIL-NET.md` - the NET 1 capture record + byte-freeze attestation + the raw leads routed to 391-02

## Decisions Made

- **RNG-01..06 left unmarked at this plan.** NET 1 on record is one half of the dual-net method; the per-item no-finding/finding verdict requires BOTH nets on record and is issued at 391-02 (NET 2 Claude + adjudication + skeptic gate). Marking them now would be premature. This matches the 389/390 Wave-1 precedent (the FINDINGS verdict + req attestation came at the Wave-2 plan).
- **Charged the §6-prime decimator distribution target hard.** The prompt forbids a hand-wave on RNG-02/FC-391-04 and demands a real distribution argument over the whole winning-bucket population. Both models complied (keccak full-diffusion of `hash2(uint32-word, address)` → independent/uniform per-address outcomes under the shared 32-bit salt; non-grindable because the word is drawn after address commitment).
- **Recorded the codex RNG-04 cross-round lead faithfully as RAW.** Not adjudicated, not dismissed — routed to 391-02 with the skeptic-gate framing pre-noted (codex itself rated it INFO/LOW and "not a freeze/manipulability break"; no player control over either `uint32` word; off the ETH/`claimablePool` spine).

## Deviations from Plan

None - plan executed exactly as written. Both tasks' automated verifications passed on the first run; both CLIs available (no skip-handling branch needed); the subject stayed byte-frozen throughout.

## Issues Encountered

None. The council fan-out completed cleanly (exit 0, both models, 0 skipped). gemini stopped at the research stage and asked for confirmation before drafting a formal report (its SOUND verdicts are RAW, as expected for a council net) — captured as such in the NET record; this is normal council behavior, not a failure.

## Threat-model dispositions (this plan)

- **T-391-01 (tampering of the byte-frozen subject):** mitigated — `git diff a8b702a7 -- contracts/` empty + `git status --porcelain contracts/` empty after the fan-out; the council ran in read-only wrappers and wrote only to its out-dir.
- **T-391-02 (a slice silently treated as on-record with both CLIs unavailable):** does not apply — both CLIs were available (`skipped[]` empty); the both-unavailable surface-and-re-run condition was not triggered.
- **T-391-03 (`hardhat compile --force`):** avoided — only `git show` / read tools touched the subject; no hardhat invoked.

## User Setup Required

None - no external service configuration required (the gemini + codex CLIs were already installed and authed at `~/.local/bin`).

## Next Phase Readiness

- **391-02 (NET 2 Claude + adjudication) is unblocked.** NET 1 is on record; 391-02 runs the independent Claude adversarial backward-trace over every new/changed RNG consumer, adjudicates RNG-01..06 + FC-391-01..05 + the 2 inherited cross-refs vs frozen `a8b702a7`, applies the skeptic gate, and writes the 391-FINDINGS.md verdict table. The PRIORITY adjudication item: the codex RNG-04 cross-round `uint32` claim-seed collision divergence (settle material-vs-benign with the skeptic dual-gate, jointly with the RNG-02 distribution prime since both touch the same dropped-`amount` + `uint32` narrowings). The convergent-SOUND items (RNG-01/02/03/05/06 + FC-391-02/-03/-05 + FC-389-05/FC-392-11) need a Claude-net re-attestation to reach both-nets-on-record.
- No blockers. Subject byte-frozen.

## Self-Check: PASSED

All created files exist (391-01-COUNCIL-PROMPT-RNG.md, council/rng.{gemini,codex}.txt, council/rng.council.json, 391-01-COUNCIL-NET.md, 391-01-SUMMARY.md); both task commits exist (`bb0c85bc`, `61b55436`); subject byte-frozen (`git diff a8b702a7 -- contracts/` empty).

---
*Phase: 391-rng-spine*
*Completed: 2026-06-15*
