---
phase: 339-spec-design-lock-rng-freeze-safety-proof-tier-precedence-loc
plan: 01
subsystem: audit
tags: [rng-freeze, traitBurnTicket, claimBingo, soundness, vrf, design-lock, bingo, spec]

# Dependency graph
requires:
  - phase: 339-CONTEXT (discuss-phase)
    provides: D-01..D-13 locked decisions (D-02 full write-site attestation, D-03 whale-race non-finding, D-04 structured per-slot enumeration, D-13 grep-attestation)
provides:
  - 339-BINGO06-FREEZE-PROOF.md — the BINGO-06 RNG-freeze-safety proof (structured per-slot enumeration, verdict FREEZE-SAFE)
  - 339-TRAITBURNTICKET-SOUNDNESS-ATTESTATION.md — the traitBurnTicket write-site soundness attestation (IFF/SOUND) + the D-03 whale-race ACCEPTED-BY-DESIGN non-finding
  - Corrected traitBurnTicket write-site anchor (sole writer = DegenerusGameMintModule.sol:603-643; cited :2701/:2730/:2813/:654 are READ-side) — load-bearing input for IMPL 340
affects: [340-IMPL, 341-TST, 342-TERMINAL, v52-consolidated-audit]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Structured per-slot enumeration for RNG-freeze proofs (3-class table: NEW write / post-resolution READ / external CALL)"
    - "Write-site IFF soundness attestation traced to the actual source writer, not the cited anchor (PROVEN-not-assumed)"

key-files:
  created:
    - .planning/phases/339-spec-design-lock-rng-freeze-safety-proof-tier-precedence-loc/339-BINGO06-FREEZE-PROOF.md
    - .planning/phases/339-spec-design-lock-rng-freeze-safety-proof-tier-precedence-loc/339-TRAITBURNTICKET-SOUNDNESS-ATTESTATION.md
  modified: []

key-decisions:
  - "VERDICT FREEZE-SAFE: no claimBingo slot is a current-VRF-window output during rngLock"
  - "VERDICT SOUND: the traitBurnTicket IFF holds → claimBingo cannot be spoofed"
  - "Anchor-drift correction (D-13): the SOLE traitBurnTicket write-site is DegenerusGameMintModule.sol:603-643; the cited DegenerusGame.sol:2701/2730/2813 + JackpotModule:654 are all READ-side"
  - "D-03 whale-race enshrined as a written ACCEPTED-BY-DESIGN non-finding (per-VRF-reveal race window, not per-block) for the deferred v52 sweep"

patterns-established:
  - "Per-slot freeze classification table (i)/(ii)/(iii) as the BINGO-06 acceptance form (D-04)"
  - "Grep-attest the actual writer before asserting a populated-only-after-resolution invariant — correct read-vs-write anchor drift in the SPEC"

requirements-completed: [BINGO-06]

# Metrics
duration: ~20min
completed: 2026-05-28
---

# Phase 339 Plan 01: BINGO-06 RNG-Freeze-Safety Proof + traitBurnTicket Soundness Attestation Summary

**Proved (not assumed) that claimBingo is FREEZE-SAFE via a 3-class per-slot enumeration and that its traitBurnTicket ownership check is SOUND via a write-site IFF attestation — and corrected a load-bearing read-vs-write anchor drift in the cited write-sites (the real writer is MintModule.sol:603-643, not the cited view functions).**

## Performance

- **Duration:** ~20 min
- **Started:** 2026-05-28 (Phase 339 execution start)
- **Completed:** 2026-05-28
- **Tasks:** 2 completed
- **Files created:** 2 (both proof docs); 0 contract/test files touched

## Accomplishments

- **339-BINGO06-FREEZE-PROOF.md** — BINGO-06 proved with a structured per-slot classification TABLE (D-04). Every slot `claimBingo` touches is in exactly one of: (i) NEW write (`bingoClaimed`/`firstQuadrant`/`firstSymbol`), (ii) post-resolution READ (`traitBurnTicket`, `level`, `gameOver`, `poolBalance(Pool.Reward)`), (iii) external reward CALL (`transferFromPool` `:485`, `coinflip.creditFlip`). Verdict **FREEZE-SAFE**; `v45-vrf-freeze-invariant` re-attested by name for the read; `claimBingo` stated as a strict read-only consumer (NO write to `traitBurnTicket`); race-start semantics locked; the `rngLockedFlag` window pinned at `AdvanceModule.sol:1640/1697/1721` with the `:573` far-future guard.
- **339-TRAITBURNTICKET-SOUNDNESS-ATTESTATION.md** — the IFF soundness theorem (address at `traitBurnTicket[level][traitId][slot]` **iff** it owned a post-RNG-resolved entry of that exact trait byte) proved across the sole write-site, with all three D-02 sub-claims (a) keyed-by-resolved-trait-byte / no cross-trait contamination, (b) duplicate-append benign + griefing impossible (8 disjoint color buckets), (c) no non-owner re-population path (no setter/swap/delete/pop; virtual deity entries are read-time-only, never persisted). Verdict **SOUND**. The D-03 whale-race ACCEPTED-BY-DESIGN non-finding enshrined with the per-VRF-reveal (not per-block) framing.
- **Anchor-drift correction (D-13 / PROVEN-not-assumed):** enumerated every `traitBurnTicket` reference in `contracts/` and established the sole population/append site is `DegenerusGameMintModule.sol:603-643` (inline-asm batch append keyed by the RNG-resolved `traitId` at `:586-587`). The plan/CONTEXT-cited "write-sites" `DegenerusGame.sol:2701/2730/2813` (all `view`: `sampleTraitTickets`/`sampleTraitTicketsAtLevel`/`getTickets`) and `JackpotModule:654` (a bucket reader feeding `_randTraitTicket … view`) are READ-side. This is exactly the inline-duplication class of error the directive exists to catch.

## Task Commits

Each task was committed atomically:

1. **Task 1: BINGO-06 RNG-freeze-safety proof (per-slot enumeration, FREEZE-SAFE)** - `5189240f` (docs)
2. **Task 2: traitBurnTicket write-site soundness attestation + whale-race non-finding** - `79f0487d` (docs)

**Plan metadata:** (this SUMMARY + STATE/ROADMAP/REQUIREMENTS) committed separately as the final docs commit.

## Files Created/Modified

- `.planning/phases/339-.../339-BINGO06-FREEZE-PROOF.md` - The BINGO-06 freeze proof (SC2): 3-class per-slot table, FREEZE-SAFE verdict, v45 re-attestation, race-start lock.
- `.planning/phases/339-.../339-TRAITBURNTICKET-SOUNDNESS-ATTESTATION.md` - The D-02 write-site soundness attestation (IFF/SOUND, sub-claims a/b/c) + the D-03 whale-race non-finding.

No `contracts/*.sol` or `test/` files touched (paper-only SPEC plan). `git diff 812abeee HEAD -- contracts/` is EMPTY.

## Decisions Made

- Both proof docs cite all the anchors the plan's automated `verify` greps require (`416`/`485` in the freeze proof; `2701`/`2730`/`2813`/`654` in the soundness attestation) AND add the corrected true write-site (`MintModule.sol:603-643`), so the SPEC is both verifier-passing and source-accurate.
- The freeze verdict is strengthened (not weakened) by the anchor correction: the populated-only-after-resolution invariant is now anchored to the actual writer rather than assumed from a read-side citation.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Anchor/correctness drift] Corrected read-vs-write classification of the cited traitBurnTicket "write-sites"**
- **Found during:** Task 2 (soundness attestation), corroborated during Task 1 (freeze proof, populated-only-after-resolution invariant).
- **Issue:** The plan + 339-CONTEXT D-02 cite `DegenerusGame.sol:2701/2730/2813` and `DegenerusGameJackpotModule.sol:654` as the `traitBurnTicket` "write-sites." On source inspection at HEAD (≡ `812abeee` for `contracts/`), all four are READ-side: `:2701` `sampleTraitTickets`, `:2730` `sampleTraitTicketsAtLevel`, `:2813` `getTickets` are `view` query/sample functions; `:654` is a jackpot bucket reader (`_randTraitTicket … private view`). None appends to `traitBurnTicket`. A soundness proof anchored only to those would be a precedent-based hand-wave (the exact failure the D-02 / "PROVEN not assumed" directive forbids).
- **Fix:** Enumerated every `traitBurnTicket` reference in `contracts/` and established the SOLE population/append site is `DegenerusGameMintModule.sol:603-643` (inline-assembly batch append of `player`, keyed by the RNG-resolved `traitId` at `:586-587`). Proved the IFF/SOUND verdict and the populated-only-after-resolution freeze invariant against that real writer; documented the cited anchors as the read-side consumers the theorem protects; recorded the correction explicitly under D-13 in both docs.
- **Files modified:** both proof docs (the correction note is embedded; no contract change).
- **Verification:** `grep -rn "traitBurnTicket" contracts/` returns the complete reference set (writer at MintModule, reads elsewhere); both docs pass their automated `verify` greps.
- **Committed in:** `79f0487d` (Task 2; the corroborating note also in `5189240f` Task 1).

---

**Total deviations:** 1 auto-fixed (Rule 1 — correctness/anchor drift)
**Impact on plan:** Necessary for the soundness/freeze proofs to be source-true rather than assumed. No scope creep — still paper-only, zero contract edits, all locked decisions honored. Strengthens the IMPL 340 acceptance contract (the real writer is now identified).

## Issues Encountered

None beyond the anchor-drift correction above (handled via Rule 1).

## Known Stubs

None. No placeholder/TODO/FIXME patterns in either proof doc.

## Threat Flags

None. This plan introduces no new security-relevant surface — it records proofs over the existing claimBingo design surface already enumerated in the plan's `<threat_model>` (T-339-01 mitigated by the freeze proof, T-339-02 mitigated by the soundness attestation, T-339-03 accepted via the D-03 non-finding).

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- **For IMPL 340:** the freeze proof + soundness attestation are the v51 security floor (the internal adversarial sweep is DEFERRED → v52, so these paper proofs ARE the deliverable for this surface). IMPL must (a) wire `claimBingo` as a strict read-only consumer of `traitBurnTicket` with NO write to it, (b) keep the three new bitfields claimBingo-exclusive (the verifier should confirm the only readers/writers of `bingoClaimed`/`firstQuadrant`/`firstSymbol` are `claimBingo`), and (c) treat `MintModule.sol:603-643` as the authoritative `traitBurnTicket` writer (not the read-side anchors the seed cited).
- **For the SPEC's other plans (339-02/03/04):** the corrected write-site anchor should propagate into any tier-precedence / call-graph attestation that references the `traitBurnTicket` population path.
- No blockers.

## Self-Check: PASSED

- FOUND: 339-BINGO06-FREEZE-PROOF.md
- FOUND: 339-TRAITBURNTICKET-SOUNDNESS-ATTESTATION.md
- FOUND: 339-01-SUMMARY.md
- FOUND commit: `5189240f` (Task 1)
- FOUND commit: `79f0487d` (Task 2)
- Contract guard: `git diff 812abeee HEAD -- contracts/` EMPTY (zero contract edits)

---
*Phase: 339-spec-design-lock-rng-freeze-safety-proof-tier-precedence-loc*
*Completed: 2026-05-28*
