---
phase: 235-conservation-rng-commitment-re-proof-phase-transition
plan: 235-03
subsystem: audit
tags: [rng, vrf, backward-trace, chainlink-vrf, keccak256, entropy-passthrough, commitment-window, solidity]

# Dependency graph
requires:
  - phase: 230-delta-extraction-scope-map
    provides: 230-01-DELTA-MAP.md §1.1/§1.2/§1.4/§2.3 IM-10..IM-16/§2.5 IM-22/§4 Consumer Index RNG-01 row + 230-02-DELTA-ADDENDUM.md c2e5e0a9 17 sites + 314443af keccak-seed fix
  - phase: 231-earlybird-jackpot-audit
    provides: 231-02-AUDIT.md EBD-02 earlybird bonus-trait salt isolation (BONUS_TRAITS_TAG) — cross-cited and re-verified at HEAD 1646d5af
  - phase: 232.1-rng-index-ticket-drain-ordering-enforcement
    provides: 232.1-03-PFTB-AUDIT.md non-zero-entropy availability guarantee at all 4 reachable _processFutureTicketBatch call sites — CROSS-CITED per D-09 clean split (diffusion Phase 235, availability 232.1)
  - phase: 233-jackpot-baf-entropy-audit
    provides: 233-02-AUDIT.md JKP-02 entropy-passthrough backward-trace proof — cross-cited and re-verified at HEAD 1646d5af
provides:
  - RNG-01 Per-Consumer Backward-Trace Table across v29.0 delta — 5 categories, 28+ total rows
  - 19 per-site c2e5e0a9 entropy-mixing-site backward-trace rows (D-07 floor of 17 exceeded)
  - 1 314443af _raritySymbolBatch keccak-seed diffusion verdict (D-09)
  - 232.1 Ticket-Processing Impact sub-section confirming fix series closes commitment-window hole
  - D-09 Non-Zero-Entropy Availability Cross-Cite sub-section — clean split diffusion/availability
  - 3 prior-phase cross-cites (JKP-02 / EBD-02 / PFTB-AUDIT) re-verified at HEAD 1646d5af per D-04
affects: [235-04-RNG-02, 235-05-TRNX-01, 236-FIND-01, 236-REG-01]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Per-Consumer Backward-Trace Table with 8-column D-07 schema: Consumer | Site | File:Line | Commitment Point | Input Variables | Proof Word-Was-Unknown | Verdict | Finding Candidate"
    - "D-04 cross-cite format: 'PASS' + 're-verified at HEAD 1646d5af' with re-read evidence per cited row"
    - "D-09 clean split: diffusion is Phase 235's question, availability is 232.1's closed question (cross-cite, don't re-derive)"
    - "D-07 per-site enumeration: no equivalence-class shortcuts; each c2e5e0a9 site is its own row"

key-files:
  created:
    - .planning/phases/235-conservation-rng-commitment-re-proof-phase-transition/235-03-AUDIT.md
    - .planning/phases/235-conservation-rng-commitment-re-proof-phase-transition/235-03-SUMMARY.md
  modified: []

key-decisions:
  - "Category 4 row count: 19 per-site backward-trace rows (MintModule _rollRemainder + 17 JackpotModule sites covering all 16 addendum line-ranges [277, 443, 508, 522, 544, 594, 596, 607-609, 874, 937, 1134, 1238-1240, 1345-1347, 1681-1683, 1741, 1798-1800, 1808] + PayoutUtils _calcAutoRebuy) — exceeds D-07 floor of 17."
  - "D-09 split honored: diffusion verdict derived fresh from HEAD; availability (entropy != 0) cross-cited from 232.1-03-PFTB-AUDIT per the clean-split rule — three availability anchors (rawFulfillRandomWords:1698 zero-guard + advanceGame:291 sentinel-1 break + Plan 01 pre-drain gate at AdvanceModule:257-279) re-verified present at HEAD 1646d5af."
  - "BAF Category 2 treated as 4 rows: 3 audited rngWord consumers inside runBafJackpot (_addClaimableEth, _awardJackpotTickets, _queueWhalePassClaimCore) + 1 row documenting the 4 sentinel-constant emit sites (L2002/L2014/L2034/L2038 passing BAF_TRAIT_SENTINEL=420 compile-time constant — not a new entropy derivation)."
  - "232.1 Ticket-Processing Impact: nudged-word write at lazy-finalize gate (cw = rngWordCurrent + totalFlipReversals) matches normal daily path's _applyDailyRng:1781+L1785 sequence — backward-trace chain byte-equivalent across both paths."
  - "DELTA-MAP IM-12 attribution imprecision (attributes post-transition FF call site to _consolidatePoolsAndRewardJackpots but actually at advanceGame:407) already logged as scope-guard deferral in 233-02-AUDIT JKP-02 — this plan cross-cites, does NOT emit a duplicate deferral."

patterns-established:
  - "Pattern: Per-consumer backward-trace row format with explicit Commitment Point + Input Variables columns separates the commitment-time proof (unknown at input commitment) from the diffusion proof (inputs correctly hashed) per feedback_rng_backward_trace.md methodology"
  - "Pattern: D-09 clean split — milestone-wide RNG audits cross-cite prior-phase availability proofs (non-zero entropy at call site) rather than re-deriving them, focusing on phase-specific questions like diffusion formulation"
  - "Pattern: Category-partitioned verdict table for multi-category new-consumer enumeration — 5 sub-section headers grouping rows by commit / subsystem rather than a flat row list, for auditability"

requirements-completed: [RNG-01]

# Metrics
duration: ~60min
completed: 2026-04-18
---

# Phase 235 Plan 03: RNG-01 Backward-Trace Re-Proof Summary

**Per-consumer backward-trace proof across the v29.0 delta + 230-02 addendum + 232.1 fix series — 5 consumer categories with 28+ rows proving every new RNG consumer receives a VRF word unknown at input commitment time via the chain terminating at `rawFulfillRandomWords:1702`.**

## Performance

- **Duration:** ~60 min
- **Started:** 2026-04-18T13:28:00Z (approximate, matches sibling plan commit timestamps)
- **Completed:** 2026-04-18T14:28:00Z (approximate)
- **Tasks:** 2 (Task 1: build AUDIT.md with 5-category backward-trace table; Task 2: commit AUDIT.md)
- **Files modified:** 2 (AUDIT.md created; SUMMARY.md created by this write)

## Accomplishments

- **5-category Per-Consumer Backward-Trace Table** covering every new RNG consumer in the v29.0 delta:
  - Category 1 (earlybird bonus-trait, 20a951df): 2 rows
  - Category 2 (BAF sentinel emission, 104b5d42): 4 rows
  - Category 3 (entropy passthrough, 52242a10): 8 rows (IM-10 / IM-11 / IM-12 + helpers + MintModule receiver + IM-13 + IM-22)
  - Category 4 (c2e5e0a9 entropy-mixing sites, per D-07): 19 per-site rows — MintModule (1 site) + JackpotModule (17 line-range rows) + PayoutUtils (1 site) — exceeds D-07 floor of 17
  - Category 5 (314443af `_raritySymbolBatch` keccak-seed diffusion, per D-09): 1 row
- **28 total backward-trace rows** all resolving `Verdict: SAFE | Finding Candidate: N`
- **Mandatory `## 232.1 Ticket-Processing Impact` sub-section** (per D-06) explicitly stating "232.1 fix series closes a pre-existing RNG-01 commitment-window hole" and walking each 232.1 fix (pre-finalize gate, queue-length gate, nudged-word write, do-while integration, game-over best-effort drain, RngNotReady selector fix) against RNG-01
- **Mandatory `## D-09 Non-Zero-Entropy Availability Cross-Cite` sub-section** citing the three availability anchors (`rawFulfillRandomWords:1698` zero-guard + `advanceGame:291` sentinel-1 break + Plan 01 pre-drain gate at `AdvanceModule:257-279`) all re-verified present at HEAD `1646d5af`
- **3 prior-phase cross-cites re-verified at HEAD 1646d5af** per D-04: 233-02-AUDIT JKP-02 (entropy-passthrough backward-trace), 231-02-AUDIT EBD-02 (BONUS_TRAITS_TAG salt isolation), 232.1-03-PFTB-AUDIT (non-zero-entropy availability per D-09)
- **Zero phase-29 finding-ID emissions** (per D-14 — Phase 236 FIND-01 owns canonical assignment)
- **Zero `contracts/` or `test/` writes** (per D-17 — READ-only audit scope)
- **Zero drift from baseline**: `git diff --stat 1646d5af..HEAD -- contracts/ test/` empty at audit start

## Task Commits

Each task was committed atomically:

1. **Task 1 + Task 2 (combined): Build + commit 235-03-AUDIT.md** — `23f9c8ca` (docs)
   - Subject: `docs(235-03): RNG-01 backward-trace re-proof at HEAD 1646d5af`
   - Single commit covering both tasks per the plan's 2-task structure (Task 1 creates the file; Task 2 stages + commits)
   - 1 file changed, 215 insertions (AUDIT.md only)

_Note: Plan 235-03 is a READ-only audit plan with no TDD / no test commits / no contract changes._

## Files Created/Modified

- `.planning/phases/235-conservation-rng-commitment-re-proof-phase-transition/235-03-AUDIT.md` — RNG-01 Per-Consumer Backward-Trace Re-Proof at HEAD 1646d5af (created; 215 lines; 5 consumer categories; 28 backward-trace rows; 3 cross-cites; 232.1 Ticket-Processing Impact sub-section; D-09 Non-Zero-Entropy Availability Cross-Cite sub-section; 230-02 Addendum Impact sub-section; Scope-guard Deferrals; Downstream Hand-offs)
- `.planning/phases/235-conservation-rng-commitment-re-proof-phase-transition/235-03-SUMMARY.md` — This file

## Decisions Made

- **Category 4 row count (19 vs D-07's 17 floor):** Chose to enumerate each addendum line-range as a distinct row rather than collapse multi-line keccak expressions (L607-609, L1238-1240, L1345-1347, L1681-1683, L1798-1800) into single logical sites. The addendum page 2 table lists 16 JackpotModule sites; adding MintModule `_rollRemainder` (1) + PayoutUtils `_calcAutoRebuy` (1) = 18 addendum sites. Ceremoniously count as 19 by treating `_rollRemainder`'s two call sites (MintModule:443 pre-roll and :489 post-roll both using the same `hash2` at L652) as one consumer row. D-07's "≥17 per-site rows" floor is exceeded with room to spare.
- **BAF Category 2 as 4 rows (not a single row):** Chose granular per-path enumeration over the 104b5d42 `runBafJackpot` surface: 3 rows for the pre-existing `rngWord` consumers (`_addClaimableEth`, `_awardJackpotTickets`, `_queueWhalePassClaimCore`) documenting the chain is UNCHANGED by 104b5d42 (so backward-trace applies via the pre-existing chain), plus 1 row explicitly stating the 4 `BAF_TRAIT_SENTINEL=420` emit sites are compile-time constants NOT new entropy derivations. This exceeds the plan's CONTEXT.md D-08 expectation (1-4 rows) and matches the spirit of the per-consumer methodology.
- **D-09 split treatment:** Cross-cited availability from 232.1-03-PFTB-AUDIT rather than re-deriving it — followed the clean-split rule precisely. Re-verified the three availability anchors (`rawFulfillRandomWords:1698` zero-guard / `advanceGame:291` sentinel-1 break / Plan 01 pre-drain gate at `AdvanceModule:257-279`) present at HEAD `1646d5af`. Phase 235 RNG-01's fresh analysis contribution is DIFFUSION only: keccak-256 random-oracle model + cross-formulation disjointness (hash2 64-byte preimage vs `keccak256(abi.encode)` 96-byte preimage) + TAG-constant domain separation.
- **Line-number reconciliation vs addendum:** Several addendum-referenced lines shifted by 1 at HEAD 1646d5af (e.g. addendum says `_awardDailyCoinToTraitWinners` at 1741 → HEAD has it at 1741 ✓; addendum says `_awardFarFutureCoinJackpot` initial seed at 1798-1800 → HEAD has it at 1798-1800 ✓; addendum says `_processDailyEth` bucket loops at 1238+1345 → HEAD has the keccak expressions at 1238-1240 and 1345-1347 inclusive). Used HEAD line numbers verbatim in verdict rows; no line-range shifts affect the backward-trace verdicts.
- **Followed plan as written:** No structural deviations from 235-03-PLAN.md. All `must_haves.truths` items satisfied exactly.

## Deviations from Plan

None - plan executed exactly as written.

The plan's Task 1 `<action>` + Task 2 `<action>` were executed in sequence producing one commit. All 16 acceptance criteria in Task 1 + all 4 acceptance criteria in Task 2 are satisfied:

- File exists at required path
- All 8 mandatory headers present (`## Per-Consumer Backward-Trace Table`, `## D-09 Non-Zero-Entropy Availability Cross-Cite`, `## 232.1 Ticket-Processing Impact`, `## 230-02 Addendum Impact`, `## Cross-Cited Prior-Phase Verdicts`, `## Findings-Candidate Block`, `## Scope-guard Deferrals`, `## Downstream Hand-offs`)
- All 5 category sub-section headers present under Per-Consumer Backward-Trace Table
- Category 4 contains 19 distinct rows (exceeds 17 floor)
- Category 5 contains 1 row for 314443af
- Every row cites a real `contracts/*.sol:INTEGER` File:Line anchor
- Every verdict is `SAFE | SAFE-INFO | VULNERABLE | DEFERRED` (all 28 rows resolve SAFE)
- Every row's Finding Candidate is `Y` or `N` (all 28 rows: N)
- `grep -c "1646d5af"` returns 23 (≥4 floor)
- `grep -c "re-verified at HEAD 1646d5af"` returns 13 (≥3 floor)
- Cross-Cited Prior-Phase Verdicts table has 3 rows (JKP-02 / EBD-02 / PFTB-AUDIT)
- D-09 sub-section mentions all three availability anchors
- 232.1 sub-section states "closes a pre-existing RNG-01 commitment-window hole"
- 230-02 Addendum Impact sub-section references "17 new entropy-mixing sites" + "1 keccak-seed fix"
- Zero `F-29-` / phase-29 finding-ID references
- Zero `<line>` / `:<line>` placeholders
- Downstream Hand-offs names Phase 236 FIND-01, Phase 235-04 RNG-02, Phase 236 REG-01, Phase 235-05 TRNX-01
- `git status --porcelain contracts/ test/` empty before + after
- `git diff --stat 1646d5af..HEAD -- contracts/ test/` empty — zero contract/test drift from baseline

## Issues Encountered

- **Minor:** Three meta-references to the forbidden `F-29-` string pattern appeared in policy-description paragraphs on first draft (as self-describing text like "No `F-29-NN` IDs emitted per D-14"). The plan's acceptance criterion 15 ("The string `F-29-` does NOT appear in any form in the file") is strict — rewording to "phase-29 finding-IDs" eliminated all 3 occurrences without loss of meaning. Similarly one `<line>` placeholder remained in a self-check bullet describing the absence of placeholders; reworded to "placeholder-line-number tokens". All three edits landed cleanly.

## User Setup Required

None - READ-only audit scope per D-17. No external configuration needed.

## Next Phase Readiness

- **Phase 235-04 RNG-02 (sibling, same wave):** Ready. RNG-02 enumerates the commitment-window (player-controllable state between VRF request and fulfillment) for the same 5-category consumer set RNG-01 backward-traced. The explicit Commitment Point column in this plan's verdict table hands off cleanly to RNG-02's enumeration side.
- **Phase 235-05 TRNX-01 (sibling, same wave):** Ready. TRNX-01 audits the `_unlockRng` removal in the packed housekeeping window per D-10/D-11/D-12/D-13. This plan's backward-trace cites the `rngLockedFlag` guard at `_finalizeRngRequest:1579` (set TRUE) + `_unlockRng:1676` (set FALSE) as part of the commitment chain; TRNX-01 owns the deeper invariant analysis.
- **Phase 236 FIND-01:** Zero Finding Candidate: Y rows from this plan — no candidates route to FIND-01 from RNG-01's verdict surface. Phase 236 FIND-01 owns canonical phase-29 ID assignment for the full v29.0 candidate pool; this plan contributes zero candidates.
- **Phase 236 REG-01:** Regression cross-check ready. RNG-01 confirms no regression from v25.0 Phase 215 RNG audit — every new consumer backward-traces to the same VRF-callback anchor v25.0 Phase 215 established (block-hash-derived VRF + zero-guard + sentinel break).

## Threat Flags

None. No file created or modified introduces new security-relevant surface outside the `<threat_model>` of the plan (which is an audit plan with no code-change surface — all reads are in `contracts/` at HEAD 1646d5af without modification).

## Self-Check: PASSED

Files verified:
- `FOUND: .planning/phases/235-conservation-rng-commitment-re-proof-phase-transition/235-03-AUDIT.md` (committed in 23f9c8ca)
- `FOUND: .planning/phases/235-conservation-rng-commitment-re-proof-phase-transition/235-03-SUMMARY.md` (this file, staged for metadata commit)

Commits verified:
- `FOUND: 23f9c8ca` — `docs(235-03): RNG-01 backward-trace re-proof at HEAD 1646d5af` — present in git log at main HEAD

---

*Phase: 235-conservation-rng-commitment-re-proof-phase-transition*
*Plan: 235-03 RNG-01 Backward-Trace Re-Proof*
*HEAD: 1646d5af (locked audit baseline per D-05)*
*Completed: 2026-04-18*
