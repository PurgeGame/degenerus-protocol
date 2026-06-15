---
phase: 393-permissionless-composition
plan: 01
subsystem: audit
tags: [permissionless, access-control, keeper-bounty, burst-solvency, reentrancy, council, cross-model, audit-only]

# Dependency graph
requires:
  - phase: 388-foundation-subject-freeze-green-baseline
    provides: byte-frozen subject a8b702a7 + FC-393-01..04 finding-candidate ledger + the inherited cross-refs FC-390-03/-06, FC-392-08/-20
  - phase: 390-solvency-spine
    provides: the FC-390-03/-06 solvency-half REFUTALS + FC-392-08 solvency/CEI REFUTAL = the consistency anchor for the ACCESS half charged here
  - phase: 391-rng-spine
    provides: the proven NET-1 council-prompt + COUNCIL-NET capture shape + the RNG-freeze attestation (so the gate-intactness sweep need only confirm the gate is present, not re-audit the window)
  - phase: 392-entropy-and-econ
    provides: the FC-392-08 ECON cap-RMW BY-DESIGN + FC-392-20 INFO gas halves = the consistency anchor; the codex-usage-cap skip-handling precedent
provides:
  - NET 1 (cross-model council) on record for the full PERMISSIONLESS-COMPOSITION slice (ACCESS-01..05)
  - the neutral ACCESS council prompt (393-01-COUNCIL-PROMPT-ACCESS.md) charged against frozen a8b702a7
  - raw gemini traced output (codex skipped — usage cap) + the council.json manifest under council/
  - the council-net capture record (393-01-COUNCIL-NET.md) with the leads + 2 cite-drifts routed to 393-02
affects: [393-02 (NET 2 Claude + adjudication), 396 TERMINAL (both-nets-on-record consolidation + the post-reset codex re-run)]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Dual-net audit: NET 1 (council) on record FIRST so Wave-2 Claude-net + adjudication can fold the leads in before any verdict"
    - "Neutral charge of a LOW/confirmatory-class slice with two substantive primes elevated: ACCESS-02 keeper-bounty vs REAL gas (not the 0.5-gwei peg) + ACCESS-04 partial-balance burst solvency charged HARD demanding a real argument, no hand-wave"
    - "Already-adjudicated cross-ref halves stated as the consistency anchor (attack only the owned ACCESS half, do not re-derive the settled solvency/ECON half)"

key-files:
  created:
    - .planning/phases/393-permissionless-composition/393-01-COUNCIL-PROMPT-ACCESS.md
    - .planning/phases/393-permissionless-composition/council/access.gemini.txt
    - .planning/phases/393-permissionless-composition/council/access.gemini.err
    - .planning/phases/393-permissionless-composition/council/access.codex.err
    - .planning/phases/393-permissionless-composition/council/access.council.json
    - .planning/phases/393-permissionless-composition/393-01-COUNCIL-NET.md
  modified: []

key-decisions:
  - "Left ACCESS-01..05 UNMARKED — NET 1 on record does not issue a per-item verdict; the no-finding/finding verdict needs BOTH nets on record (issued at 393-02 adjudication)"
  - "Charged ACCESS-02 (keeper-bounty economics) and ACCESS-04 (partial-balance burst solvency) as dedicated numbered prime break-targets demanding a real-gas / real-burst-accounting argument, not a hand-wave — gemini complied with concrete numbers (40x at 20 gwei, 10x at 5 gwei, ~30% liquid) + the MAX_ROLL reservation trace"
  - "Recorded the codex usage-cap skip faithfully in skipped[] + flagged a post-reset codex re-run to 396 (matches the 392-01..04 codex-cap precedent); a single available model with real content satisfies council-on-record with the skip documented"
  - "Captured 2 gemini cite-drifts (the redemption bounty constant cited 24e12 vs the pinned 15e12; the carry-mint line cited :787 vs entry @366) as RAW bookkeeping leads for 393-02 to reconcile at the frozen source — NOT findings, NOT silently corrected here"

patterns-established:
  - "ACCESS council prompt: thin-dispatcher delegatecall fact + beneficiary-only doctrine + keeper-bounty-net-negative-vs-REAL-gas + un-manufacturability + forced-timing-MAGNITUDE (not the timing model) as the thesis to break, mapped to the req IDs, with the by-design exclusions (lootbox/permissionless TIMING, operator-approval trust boundary, genesis self-break, dust-drop, RTP) carried so the council does not re-litigate settled intent"

requirements-completed: []

# Metrics
duration: ~18min
completed: 2026-06-15
---

# Phase 393 Plan 01: PERMISSIONLESS-COMPOSITION NET 1 (Cross-Model Council) Summary

**NET 1 on record for the full PERMISSIONLESS-COMPOSITION slice against frozen `a8b702a7`: gemini returned a substantive traced audit VERIFYING SOUND across all of ACCESS-01..05 + FC-393-04 (0 findings) — with the real-gas keeper-bounty accounting (40x under-water at 20 gwei, ~30% liquid value) and the MAX_ROLL (175%) burst-solvency trace the two primes demanded; codex skipped on its hard usage cap (post-reset re-run flagged to 396). Two gemini cite-drifts routed raw to 393-02.**

## Performance

- **Duration:** ~18 min (council fan-out ~5 min of it)
- **Started:** 2026-06-15 (Phase 393 execution start)
- **Completed:** 2026-06-15
- **Tasks:** 2
- **Files modified:** 6 created (1 prompt + 1 gemini output + 2 err files + 1 manifest + 1 net record; 0 contract source)

## Accomplishments

- Authored the neutral PERMISSIONLESS-COMPOSITION council prompt (309 lines) charged against the byte-frozen subject `a8b702a7`, covering ACCESS-01..05 + FC-393-01..04 owned leads + the inherited cross-refs FC-390-03, FC-390-06, FC-392-08, FC-392-20, with **ACCESS-02 (keeper-bounty economics vs REAL prevailing gas + flip-credit illiquidity + un-manufacturability)** and **ACCESS-04 (partial-balance burst solvency under same-block multi-claim leg accounting)** charged HARD as the two dedicated numbered prime break-targets demanding a real argument, the beneficiary-only + forced-timing-MAGNITUDE doctrine encoded, the thin-dispatcher delegatecall fact stated, the KNOWN-BY-DESIGN exclusion list carried, and no verdict pre-stated.
- Ran the council fan-out (`council.sh --label access`) to gemini + codex in parallel; gemini OK (exit 0, 0-byte err), codex SKIPPED on a hard usage-limit cap (recorded in `skipped[]`).
- Captured the gemini raw traced output + the council.json manifest under the phase `council/` dir and wrote the council-net capture record (393-01-COUNCIL-NET.md) with the convergent-SOUND prime attestations, the 2 cite-drifts, and the post-reset codex re-run flag all routed to 393-02 / 396.
- Verified the subject byte-frozen throughout (`git diff a8b702a7 -- contracts/` empty; `git status --porcelain contracts/` empty; no stray file written anywhere by the council).

## Task Commits

Each task was committed atomically:

1. **Task 1: Author the neutral council prompt for the PERMISSIONLESS-COMPOSITION slice** - `26db45a4` (docs)
2. **Task 2: Run the council fan-out and record the council-net capture** - `5764ba0c` (docs)

**Plan metadata:** (this SUMMARY + STATE.md + ROADMAP.md) - final docs commit

## Files Created/Modified

- `.planning/phases/393-permissionless-composition/393-01-COUNCIL-PROMPT-ACCESS.md` - the neutral ACCESS council prompt (the thesis to break, mapped to ACCESS-01..05 + the FC-393 owned leads + the inherited cross-refs)
- `.planning/phases/393-permissionless-composition/council/access.gemini.txt` - gemini raw traced output (VERIFIED SOUND all ACCESS-01..05 + FC-393-04, 0 findings, with real-gas + burst-solvency numbers)
- `.planning/phases/393-permissionless-composition/council/access.gemini.err` - gemini stderr (0 bytes — exit 0)
- `.planning/phases/393-permissionless-composition/council/access.codex.err` - codex wrapper skip notice (usage-cap; the banner is in /tmp/ask-codex.err)
- `.planning/phases/393-permissionless-composition/council/access.council.json` - the manifest (models: gemini; skipped: codex)
- `.planning/phases/393-permissionless-composition/393-01-COUNCIL-NET.md` - the NET 1 capture record + byte-freeze attestation + the raw leads + cite-drifts + codex-re-run flag routed to 393-02 / 396

## Decisions Made

- **ACCESS-01..05 left unmarked at this plan.** NET 1 on record is one half of the dual-net method; the per-item no-finding/finding verdict requires BOTH nets on record and is issued at 393-02 (NET 2 Claude + adjudication + skeptic gate). This matches the 390/391/392 Wave-1 precedent (the FINDINGS verdict + req attestation came at the Wave-2 plan).
- **Charged the two substantive primes HARD against a hand-wave.** Access-control / reentrancy / MEV is the LOW/confirmatory class for this slice, but ACCESS-02 (a real faucet would be value-bearing) and ACCESS-04 (solvency-adjacent burst accounting) were elevated to dedicated numbered break-targets demanding real-gas numbers and a same-block multi-claim leg-accounting argument. gemini complied: 40x under-water at 20 gwei / 10x at 5 gwei / ~30% liquid value + un-manufacturability for ACCESS-02; the MAX_ROLL (175%) reservation shifting any ETH-drain deficit to the stETH leg of the same reservation for ACCESS-04.
- **Recorded the codex usage-cap skip faithfully.** Not a refusal or classifier trip — a hard account cap ("try again at 11:56 PM"), the same cap that skipped codex at 392-01..04. A single available model (gemini) with real content satisfies council-on-record with the skip documented in `skipped[]`; a post-reset codex re-run is flagged to 396 (opportunistic at 393-02 if reset).
- **Captured 2 gemini cite-drifts as RAW bookkeeping, not findings.** gemini cited the redemption bounty constant as `24e12` wei (~48k gas) vs the pinned `15e12`, and the `claimCoinflipCarry` mint at `:787` vs the entry @366. Routed to 393-02 to reconcile at the frozen source; the no-finding direction is unaffected (the bounty is net-negative vs real gas at either constant) but the constant must be pinned before any verdict.

## Deviations from Plan

None - plan executed exactly as written. Both tasks' automated verifications passed on the first run. The codex usage-cap skip was anticipated by the plan (codex capped since 392) and handled via the documented skip-handling branch (recorded in `skipped[]` + flagged to 396), not a deviation.

## Issues Encountered

None blocking. codex hit a hard usage-limit cap and skipped (anticipated — same cap as 392-01..04); gemini covered the slice with a substantive traced audit, so the dual-NET is satisfied (council on record) with the codex skip documented and a post-reset re-run flagged. gemini's cites are working-tree-derived rather than strictly via `git show` (fine for RAW capture — 393-02 re-reads the frozen source for every cite); the 2 cite-drifts are captured for reconciliation.

## Threat-model dispositions (this plan)

- **T-393-01 (tampering of the byte-frozen subject):** mitigated — `git diff a8b702a7 -- contracts/` empty + `git status --porcelain contracts/` empty after the fan-out; the council ran in read-only wrappers and wrote only to its out-dir; no stray file written anywhere in the tree.
- **T-393-02 (a slice silently treated as on-record with both CLIs unavailable):** does not apply — gemini is available with a real audit; the codex skip is documented in `skipped[]` and surfaced (not silently passed) with a recommended post-reset re-run to 396.
- **T-393-03 (`hardhat compile --force`):** avoided — only `git show` / read tools touched the subject; no hardhat invoked.

## Known Stubs

None - this plan creates only `.planning/` audit documents (the council prompt, the raw council output, the manifest, the net-record). No contract source, no application code, no stubs.

## User Setup Required

None - no external service configuration required (the gemini + codex CLIs were already installed and authed; codex's usage cap is an account-side limit that resets on its own, not a setup gap).

## Next Phase Readiness

- **393-02 (NET 2 Claude + adjudication) is unblocked.** NET 1 is on record; 393-02 runs the independent Claude adversarial sweep over every new/widened permissionless entrypoint, adjudicates ACCESS-01..05 + FC-393-01..04 + the inherited cross-refs vs frozen `a8b702a7`, applies the skeptic gate, and writes the 393-FINDINGS.md verdict table. The PRIORITY adjudication items: re-verify the redemption bounty constant at the frozen source (gemini's 24e12 vs the pinned 15e12 cite-drift) + re-attest the two convergent-SOUND primes (ACCESS-02 real-gas faucet test + ACCESS-04 same-block burst leg accounting) against the Claude net + (if reconstructable) a burst oracle. The remaining convergent-SOUND items (ACCESS-01/-03/-05 + FC-393-01/-02/-04 + the inherited cross-refs) need a Claude-net re-attestation to reach both-nets-on-record.
- A post-reset codex re-run is carried to 396 (opportunistic at 393-02 if the cap has reset) to second-source the gemini SOUND verdicts on the two primes.
- No blockers. Subject byte-frozen.

## Self-Check: PASSED

All created files exist (393-01-COUNCIL-PROMPT-ACCESS.md, council/access.gemini.txt, council/access.gemini.err, council/access.codex.err, council/access.council.json, 393-01-COUNCIL-NET.md, 393-01-SUMMARY.md); both task commits exist (`26db45a4`, `5764ba0c`); subject byte-frozen (`git diff a8b702a7 -- contracts/` empty).

---
*Phase: 393-permissionless-composition*
*Completed: 2026-06-15*
