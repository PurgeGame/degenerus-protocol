---
phase: 389-packing-identity
plan: 02
subsystem: testing
tags: [audit, claude-net, dual-net, storage-packing, gas-identity, adjudication, skeptic-gate, byte-freeze]

# Dependency graph
requires:
  - phase: 389-packing-identity
    provides: "NET 1 (cross-model council) on record for STORAGE-01..07 + GASID-01..05 + the raw leads to fold (389-01-COUNCIL-NET.md + council/*.txt)"
  - phase: 388-foundation-subject-freeze-green-baseline
    provides: "byte-frozen subject a8b702a7, the FC-389-01..09 intake ledger, the authoritative 388-01 LAYOUT-KEY, the green oracle REGRESSION-BASELINE-v63 (854/0/110)"
provides:
  - "NET 2 (the Claude adversarial net) ON RECORD for the STORAGE + GASID surface, independent of the council, with a per-item break attempt + provisional verdict"
  - "389-FINDINGS.md — the phase-389 adjudication: both-nets-on-record per slice, per-item verdict table (all 12 reqs + 9 leads), skeptic gate (0 HIGH), routing"
  - "STORAGE-04 / FC-389-01 settled by a cursor-lag proof (no third live EV-cap key reachable)"
  - "STORAGE-06 / FC-389-04 = 1 CONFIRMED LOW oracle-integrity finding (R-389-01, 2 stale test harnesses) DOCUMENTED + ROUTED test-only"
  - "0 CONFIRMED contract findings; STORAGE-01..05/07 + GASID-01..05 ATTESTED at a8b702a7"
affects: [390-solvency-spine, 391-rng-spine, 396-terminal, packing-identity-verdict, both-nets-on-record-gate]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "dual-net adjudication: NET 2 (Claude) attacked independently, then folded the council leads; both nets attested before the verdict"
    - "fresh forge inspect storageLayout used as the slot-truth oracle to refute/confirm each STORAGE-06 harness candidate"

key-files:
  created:
    - .planning/phases/389-packing-identity/389-02-CLAUDE-NET.md
    - .planning/phases/389-packing-identity/389-FINDINGS.md
  modified:
    - .planning/STATE.md
    - .planning/ROADMAP.md
    - .planning/REQUIREMENTS.md

decisions:
  - "STORAGE-04 / FC-389-01 REFUTED via a cursor-lag proof: deferred human opens write NO EV cap (cap drawn at deposit), every cap write keys live level+1, and level is +1-monotone (sole writer advanceGame) -> the live key set is provably subset {currentLevel, currentLevel+1}; no third live key reachable; the 10 ETH per-level cap cannot be re-earned"
  - "STORAGE-06 / FC-389-04 = 1 CONFIRMED LOW oracle-integrity finding (R-389-01): Composition handler MINT_PACKED_SLOT=10 (mintPacked_ is slot 9) -> vacuous gap-bit canary; HeroOverride JS LOOTBOX_RNG_PACKED_SLOT=35 (lootboxRngPacked is slot 34) -> seedLootboxRngIndex no-ops; both vs fresh forge inspect; test-only fix, contract unaffected"
  - "the council box-cursor stale-slot candidate (slots 58/59) REFUTED by fresh forge inspect: boxCursor@58 off7, boxCursorIndex@58 off13, boxPlayers@59 -> harnesses are CORRECT"
  - "FC-389-03 settled: the decimator accumulator stores EFFECTIVE burns (e.burn = prev + effectiveAmount; delta = effectiveAmount); DecClaimRound.totalBurn comment is CORRECT; the imprecise comment is DecEntry.burn (INFO); the storage-map FA-3 raw-framing was itself the error"
  - "STORAGE-07: capBucketCounts bounds to <= maxTotal by the trim/remainder construction + 250-clamp + remainder-share double-defense; the '+4' is a TEST-slack constant, NOT a contract property (capBucketCounts byte-identical to baseline)"
  - "skeptic gate = 0 HIGH; the prime MED-attention lead FC-389-01 fails EV condition (1) reachable; the one CONFIRMED item is LOW oracle-integrity (test-only)"

metrics:
  duration: "~1 session"
  tasks_completed: 2
  files_created: 2
  completed: 2026-06-15
---

# Phase 389 Plan 02: NET 2 (Claude adversarial net) + PACKING-IDENTITY adjudication Summary

Independent Claude adversarial net over the STORAGE + GASID packing-identity surface, folded with NET 1
(council), producing the phase-389 verdict — 0 CONFIRMED contract findings, all 12 reqs + 9 leads
adjudicated against the byte-frozen subject `a8b702a7`, with the two-window EV-cap eviction settled by a
cursor-lag proof and 1 CONFIRMED LOW oracle-integrity test-harness finding routed (test-only).

## What was built

- **`389-02-CLAUDE-NET.md` (449 lines)** — NET 2 on record: for each of STORAGE-01..07, GASID-01..05,
  and FC-389-01..09, a PROPERTY · concrete break attempt · state var + file:line at `a8b702a7` ·
  settling bound · provisional verdict. STORAGE-04 / FC-389-01 carries a dedicated cursor-lag proof;
  STORAGE-07 + GASID-02/03/04 carry concrete equivalence arguments (trim/remainder derivation,
  operand-width preimage check, nibble-table differential, single-hero trait-roll trace). The council
  leads are folded in a comparison table AFTER the independent pass.
- **`389-FINDINGS.md` (180 lines)** — the adjudication deliverable: both-nets-on-record attestation per
  slice; a per-item verdict table (CONFIRMED / REFUTED / BY-DESIGN / MONITOR) for all 21 items with the
  settling cite; the skeptic gate (0 HIGH, recorded for FC-389-01 + the CONFIRMED STORAGE-06 item);
  the §4 routing of R-389-01; the re-attestation line marking each req attested-or-finding.

## Verdict summary

- **0 CONFIRMED contract-source findings.** STORAGE-01..05, STORAGE-07, GASID-01..05 and FC-389-01/-02/
  -03/-05/-06/-07/-08/-09 all REFUTED / BY-DESIGN at `a8b702a7` with both nets on record.
- **1 CONFIRMED LOW oracle-integrity finding (R-389-01, STORAGE-06 / FC-389-04):** two stale-slot test
  harnesses (Composition `mintPacked_` slot-10 → vacuous canary; HeroOverride JS `lootboxRngPacked`
  slot-35 → no-op seed). Test-only fix, contract unaffected, forge primary baseline (854/0/110) intact.
  DOCUMENTED + ROUTED, NOT applied here.
- **STORAGE-04 / FC-389-01** (the §6 MED-attention prime target) settled by a cursor-lag proof, not
  hand-waved: deferred opens write no cap + live `level+1` keying + `level` +1-monotone ⇒ no third
  live key ⇒ the 10 ETH per-level cap cannot be re-earned.
- The council box-cursor stale-slot candidate was REFUTED by fresh `forge inspect` — NET 2 added the
  slot-truth that the box cursors live in slot 58's free bytes (off 7/13) + `boxPlayers`@59, so those
  harnesses are correct.

## Cross-references carried forward

- FC-389-05 distribution-bias half → 391 (RNG-02 / FC-391-04); narrowing-equivalence half REFUTED here.
- FC-389-02 / FC-389-08 solvency-conservation half → 390 (FC-390-01/-02/-03) + 393 (FC-393-03);
  narrowing-equivalence half REFUTED here.
- FC-389-03 INFO: `DecEntry.burn` comment imprecision (effective, not raw) — carried, no contract change.

## Deviations from Plan

None — plan executed exactly as written. Both tasks ran in order (NET 2 independent pass first, then
synthesis + skeptic gate + FINDINGS), each committed atomically with a no-contract-token message. The
plan called for a `forge inspect` slot check on the STORAGE-06 candidates; this required a `forge clean`
+ `forge build` first (storageLayout was missing from the cached artifact), run read-only — contracts
stayed byte-frozen and `ContractAddresses.sol` was not regenerated (hardhat never invoked).

## Authentication gates

None.

## Self-Check: PASSED

- `389-02-CLAUDE-NET.md` exists (449 lines, > 60 min); contains STORAGE-04, FC-389-01, GASID-03,
  STORAGE-07, capBucketCounts.
- `389-FINDINGS.md` exists (180 lines, > 80 min); contains all 21 item IDs, both-nets attestation, the
  skeptic gate.
- Commits `bbd7721c` (NET 2) and `c25978a0` (FINDINGS) exist in `git log`.
- `git diff a8b702a7 -- contracts/` EMPTY (subject byte-frozen).
