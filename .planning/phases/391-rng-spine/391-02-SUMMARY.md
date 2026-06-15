---
phase: 391-rng-spine
plan: 02
subsystem: rng-freeze-audit
tags: [audit, rng, freeze, decimator, redemption, dual-net, adjudication]
requires:
  - 391-01-COUNCIL-NET.md (NET 1 council on record)
  - 388-02-FINDING-CANDIDATES.md (FC-391-01..05 + cross-refs)
  - 388-02-ORACLE-HOLES.md (the missing decimator distribution property)
  - test/REGRESSION-BASELINE-v63.md (green oracle 854/0/110)
provides:
  - 391-02-CLAUDE-NET.md (NET 2 independent adversarial analysis)
  - 391-FINDINGS.md (phase-391 RNG-spine adjudication — both nets, all items verdicted)
  - RNG-01..06 attested at a8b702a7 (0 confirmed contract findings)
affects:
  - 392 (FC-392-11 backing-half cross-ref; FC-389-05 STORAGE-half → 389)
  - 396 TERMINAL (consolidates the RNG-spine adjudication into FINDINGS-v63.0)
tech-stack:
  added: []
  patterns: [dual-net-on-record, backward-trace-doctrine, skeptic-dual-gate, random-oracle-distribution-argument]
key-files:
  created:
    - .planning/phases/391-rng-spine/391-02-CLAUDE-NET.md
    - .planning/phases/391-rng-spine/391-FINDINGS.md
    - .planning/phases/391-rng-spine/391-02-SUMMARY.md
  modified: []
decisions:
  - "RNG-04 cross-round uint32 decimator claim-seed collision = REFUTED-as-break, benign INFO/LOW (no player control, no value extraction, off the ETH spine) — reconciles codex INFO/LOW and gemini SOUND"
  - "RNG-02/FC-391-04 decimator uint32 distribution = REFUTED (unbiased + non-grindable) by a real random-oracle argument; the missing distribution oracle is a ROUTED test-hardening item, not a contract change"
  - "RNG-05 day-boundary divergence bounded: the gate pins currentPeriod <= dailyIdx by construction so day+1 is never on-chain at burn time"
  - "0 CONFIRMED contract findings — the DOMINANT freeze class is clean across the change set; subject stays byte-frozen at a8b702a7"
metrics:
  duration: "~25 min"
  completed: "2026-06-15"
  tasks: 2
  files_created: 3
  contract_findings: 0
---

# Phase 391 Plan 02: RNG-SPINE NET 2 + Adjudication Summary

NET 2 (the independent Claude adversarial net) is on record for the full RNG-freeze surface, and the
phase-391 RNG-spine (RNG-01..06 + FC-391-01..05 + FC-389-05 / FC-392-11) is ADJUDICATED with both nets on
record, the skeptic dual-gate applied to the divergent target, and **0 CONFIRMED contract findings** — the
DOMINANT freeze/manipulability class is clean across the post-v62 change set, subject byte-frozen at
`a8b702a7`.

## What was built

- **`391-02-CLAUDE-NET.md`** — NET 2, run INDEPENDENTLY of the council (attacked freeze/entropy/replay/
  domain-separation first, folded council leads at §H). Per-consumer backward-trace to the commitment
  point (§A); the dedicated decimator uint32 distribution argument over a winner population (§B); the
  RNG-03 one-shot + survival-accumulator trace (§C); the RNG-04 cross-round collision skeptic dual-gate
  (§D); the RNG-05 day-boundary divergence bound (§E); the RNG-06 in-window SLOAD enumeration over slots
  10/34/35 + dailyIdx with the EntropyLib byte-identity + activityScore-snapshot claims attacked (§F).
- **`391-FINDINGS.md`** — the adjudication deliverable matching the just-approved 390-FINDINGS shape:
  both-nets-on-record attestation (§1); per-item verdict table for all 13 items (§2); the skeptic gate
  with the RNG-04 dual-gate (§3a) + the RNG-02/FC-391-04 distribution argument (§3b); routing (§4 — 0
  confirmed, the INFO/LOW cross-round correlation + the distribution-oracle test-hardening item routed);
  re-attestation line (§5).

## Priority adjudication outcomes (per the PRIORITY_ADJUDICATION directive)

1. **RNG-04 / codex divergence (cross-round seed collision):** pinned the exact frozen lines
   (`round.rngWord = uint32(rngWord)` DecimatorModule:277 → `hash2(rngWord, uint160(player))`
   LootboxModule:883). The cross-round collision (same player at two levels with
   `uint32(VRF_L2)==uint32(VRF_L)`) is (a) marginally reachable (~10^-5..10^-4), (b) NOT player-influenceable
   (words VRF-fixed after burn commitment), (c) yields NO value extraction (magnitude set by independent
   `amount`, same-distribution draw realized twice, off the ETH spine). **Verdict: REFUTED as a
   freeze/manip break; benign INFO/LOW** — reconciles codex (cross-round, real-but-benign) and gemini
   (within-level, SOUND).
2. **RNG-02 / FC-391-04 (decimator uint32 distribution-bias, §6 prime):** proved UNBIASED + non-grindable
   by a real random-oracle argument — each winner's `keccak256(W ‖ addr)` is an independent uniform draw,
   keccak avalanche decorrelates the shared 32-bit word from the tier-modulo low bits, the within-level
   tier histogram converges to uniform, and a multi-account actor gets independent draws with no
   shared-word edge. The missing distribution oracle is a ROUTED test-hardening item, not a contract
   change.

## No CONFIRMED HIGH/CATASTROPHE

0 freeze/manipulability breaks. No item reaches HIGH/CATASTROPHE. The orchestrator does NOT need to pause
for a USER security review on a confirmed break (there is none). The one INFO/LOW correlation (RNG-04
cross-round) and the distribution-oracle test-hardening note are DOCUMENTED + ROUTED, never fixed.

## Deviations from Plan

None — plan executed exactly as written. Both tasks ran auto; AUDIT-ONLY posture held; no contract source
touched.

## Authentication gates

None.

## Known Stubs

None — these are audit documents, not code; no data-source wiring involved.

## Self-Check: PASSED

- Created files exist: `391-02-CLAUDE-NET.md`, `391-FINDINGS.md`, `391-02-SUMMARY.md` — verified.
- Commits exist: `9e34485a` (NET 2), `33c0e478` (FINDINGS) — verified in git log.
- `git diff a8b702a7 -- contracts/` EMPTY at start, after each task, and at end — subject byte-frozen.
- All 13 items (RNG-01..06 + FC-391-01..05 + FC-389-05 / FC-392-11) carry an explicit verdict; both nets
  attested; skeptic gate applied to the two prime/divergent targets.
