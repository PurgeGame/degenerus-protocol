---
phase: 304-spec-invariant-model-spec
verified: 2026-05-19T06:00:00Z
status: passed
score: 5/5 must-haves verified
overrides_applied: 0
---

# Phase 304: SPEC + Invariant Model — Verification Report

**Phase Goal:** Formally document the per-day redemption refactor design BEFORE any contract change. Produce 304-SPEC.md covering INV-01..12 formal invariant model, SPEC-01..05 locked design decisions (with SPEC-04 a-d sub-locks), EDGE-01..18 exhaustive scenario enumeration, design-intent backward-trace + actor game-theory walk for 7 deletions (5 storage slots + UnresolvedClaim revert + redemptionPeriodIndex reset block), and source-verified citation manifest (every file:line grep-verified against contracts/StakedDegenerusStonk.sol + contracts/modules/DegenerusGameAdvanceModule.sol HEAD). Zero contract changes, zero test changes. 35 requirements covered (12 INV + 5 SPEC + 18 EDGE).
**Verified:** 2026-05-19T06:00:00Z
**Status:** PASSED
**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | 304-SPEC.md exists with §1 INV-01..12 each formally stated (storage variables + state transitions + test mapping) | VERIFIED | File exists at 960 lines. `grep -c '^### INV-'` = 12. All four labeled sub-fields (`**Formal property:**`, `**Storage variables involved:**`, `**State transitions across which the property must hold:**`, `**Test mapping:**`) each appear exactly 12 times. INV-02 includes `address(this).balance` + `steth.balanceOf` + `claimableWinnings` equation. INV-10 cites `supplySnapshot / 2`. INV-11 cites `MAX_DAILY_REDEMPTION_EV` and 160 ether. |
| 2 | §2 SPEC-01..05 locked with §2.0 Priority Statement containing 3 numbered clauses; SPEC-04 a-d sub-locks present | VERIFIED | `grep -c '^### SPEC-'` = 5. `grep -c '^### §2.0'` = 1. All three clause labels present (`1. **Hard floor`, `2. **Soft target`, `3. **Conflict resolution`). INV-01/06/07 each named in §2.0. V-184 cited 40 times across SPEC. `struct DayPending` with all 4 fields present. SPEC-02 explicitly names UnresolvedClaim revert removal. SPEC-03 names all three AdvanceModule call sites (:1230, :1293, :1323 — confirmed against source: grep returns exactly 3 hits at those lines). SPEC-04 contains 4 lettered sub-locks `(a)`, `(b)`, `(c)`, `(d)`. SPEC-05 contains `lazy-init` and `supplySnapshot == 0` initialization condition. 5 `**Lock:**` umbrella fields present. |
| 3 | §3 EDGE-01..18 each has positive + negative + INV/SPEC linkage | VERIFIED | `grep -c '^### EDGE-'` = 18. All six labeled sub-fields (Scenario, Positive assertion, Negative assertion, Tests INV-NN, Depends on SPEC-NN, Foundry function name) each appear exactly 18 times. EDGE-07 explicitly cites V-184 + RNGLOCK-FIXREC §103 + HANDOFF-111..117 (52 combined references in SPEC). EDGE-07 negative assertion states `redemptionPeriods[D].roll` byte-identical. EDGE-08 cites SPEC-04 (a); EDGE-13 cites SPEC-04 (b); EDGE-10 cites SPEC-04 (d); EDGE-14 cites SPEC-05. §1↔§3 cross-link table present with 12 INV-NN rows each having ≥1 EDGE exerciser. |
| 4 | §4 contains exactly 7 deletion subsections with 4 labeled fields each; V-184 mechanic traced in Deletions 1/4/5/7; §4 closing paragraph attests joint SPEC-01 + SPEC-03 + SPEC-04 (c) elimination | VERIFIED | `grep -c '^### Deletion [1-7]:'` = 7. All four labeled fields (`**ORIGINAL DESIGN INTENT`, `**ACTOR GAME-THEORY WALK:**`, `**POST-REFACTOR REPLACEMENT:**`, `**DELETION SAFETY ATTESTATION:**`) each appear 8 times (7 deletion subsections + 1 in §4 introductory paragraph naming the fields — documented as expected over-match in Plan 04 SUMMARY). V-184 mechanic traced in Deletion 1 (full verbatim 9-step walk), Deletion 4 (single-pool conflation enabler), Deletion 5 (BURNIE-side ~9.5% EV), Deletion 7 (STRUCTURAL ENABLER; tactic-(c) §103.C failure mode explicitly cited). Deletion 6 states composite-keying makes UnresolvedClaim STRUCTURALLY UNREACHABLE. §4 closing paragraph (lines 819-829) explicitly attests V-184 structural elimination as joint product of SPEC-01 + SPEC-03 + SPEC-04 (c), with per-lock counterfactual argument. |
| 5 | §5 citation manifest grep-verified; all 3 AdvanceModule resolveRedemptionPeriod call sites attested; no "by construction" / "trivially safe" claims; cross-section integrity check PASSED | VERIFIED | §5 has 4 sub-sections (§5.1 sStonk 50 rows, §5.2 AdvanceModule 11 rows, §5.3 integrity check, §5.4 attestation). `grep -ic 'by construction\|covered by single\|trivially safe'` = 0 across full SPEC. §5.2 explicitly enumerates all THREE AdvanceModule call sites: :1230 (primary rngGate path), :1293 (secondary mirror path), :1323 (gameover-fallback path) — confirmed against source: `grep -n 'sdgnrs.resolveRedemptionPeriod'` returns exactly 3 hits at those exact lines. §5.3 cross-section integrity check reports PASS on all 5 sub-checks. §5.4 states "ready for Phase 305 IMPL consumption". FOOTER LINE present. Plan 05 identified and reframed 6 "by construction" instances in §1/§2/§3/§4 before closing. No placeholder lines remain (`grep -c '_To be filled by Plan'` = 0). |

**Score:** 5/5 must-haves verified

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `.planning/phases/304-spec-invariant-model-spec/304-SPEC.md` | 960-line complete SPEC with §0 header + §1 INV-01..12 + §2 SPEC-01..05 + §3 EDGE-01..18 + §4 7-deletion walks + §5 citation manifest | VERIFIED | File exists, 960 lines confirmed, all sections substantive. |

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| §1 INV-NN entries | REQUIREMENTS.md INV-01..12 canonical wording | verbatim cite + formal-property restatement | VERIFIED | 35-row traceability table in §0. All 12 INV subsections present with 4-field structure. |
| §1 storage-variable enumeration | post-refactor storage layout (SPEC-01 struct shape) | named slot citation | VERIFIED | `pendingByDay[uint32 day].DayPending { uint256 ethBase; uint256 burnieBase; uint128 supplySnapshot; uint128 burned; }` present in §1 preamble and throughout. |
| §2 SPEC-NN entries | §1 INV-NN forward-references | forward-reference resolution | VERIFIED | Plan 01 SUMMARY listed 6 forward-references; Plan 02 SUMMARY confirms all 6 resolved. `grep 'per SPEC-0[1-5]'` in §1 region — all have resolvable §2 targets. |
| §2 SPEC-03 dayToResolve arg | all three AdvanceModule call sites | explicit :1230/:1293/:1323 citation | VERIFIED | Source grep confirms exactly 3 hits: line 1230, 1293, 1323. SPEC.md cites all three 11 times total. |
| §3 EDGE-NN entries | §1 INV-NN entries they exercise | "Tests INV-NN" sub-fields | VERIFIED | 12-row coverage table at end of §3. Every INV-01..12 has ≥1 EDGE exerciser. |
| §3 EDGE-07 | RNGLOCK-FIXREC §103 V-184 mechanic | verbatim attack-sequence enumeration | VERIFIED | EDGE-07 reproduces full 5-step attack trace from RNGLOCK-FIXREC §103.A. References HANDOFF-111..117. Byte-identical negative assertion present. |
| §4 deletion subsections | §2 SPEC-NN locks | POST-REFACTOR REPLACEMENT field cross-reference | VERIFIED | All 7 Deletions cite their SPEC-NN replacement (SPEC-01/02/03/04(c)/05). §2.7 cross-cutting enumeration lists all 7 items. |
| §5 citation manifest rows | every file:line citation in §1-§4 | grep-verification against source HEAD | VERIFIED | 50 sStonk rows + 11 AdvanceModule rows, all VERIFIED status, 0 CORRECTED, 0 ABSENT (per Plan 05 SUMMARY). Key source citations confirmed by verifier: `:230` = `uint32 internal redemptionPeriodIndex`, `:796-797` = UnresolvedClaim revert block, `:757-762` = reset block verbatim, `:254` = `MAX_DAILY_REDEMPTION_EV = 160 ether`, `:226-231` = deleted slots, `:221-222` = pendingRedemptions/redemptionPeriods mappings, `:588` = `uint32 period = redemptionPeriodIndex;`, `:618` = `claimRedemption()`, `:585` = `resolveRedemptionPeriod()`. |

### Data-Flow Trace (Level 4)

Not applicable. Phase 304 produces a planning document (304-SPEC.md), not a component that renders dynamic data from a runtime data source. All "data" is authored design text verified against static source files.

### Behavioral Spot-Checks

Step 7b: SKIPPED — Phase 304 has no runnable entry points. The deliverable is a specification document. The relevant executable checks are grep-verifications, which were run directly as part of the verification above and in Plan 05's §5.3 cross-section integrity check.

### Probe Execution

No probes declared or applicable. Phase 304 is a documentation-only phase (zero contract changes, zero test changes). The conventional probe path `scripts/*/tests/probe-*.sh` is for implementation/migration phases.

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|-------------|-------------|--------|----------|
| INV-01 | Plan 01 | Write-once roll immutability | SATISFIED | §1 INV-01 subsection present with formal property + storage vars + state transitions + test mapping |
| INV-02 | Plan 01 | ETH conservation (dust-bounded) | SATISFIED | §1 INV-02 with `address(this).balance + steth.balanceOf + claimableWinnings` equation present |
| INV-03 | Plan 01 | BURNIE conservation | SATISFIED | §1 INV-03 subsection present |
| INV-04 | Plan 01 | Per-day base correctness | SATISFIED | §1 INV-04 subsection present |
| INV-05 | Plan 01 | Per-day cumulative correctness | SATISFIED | §1 INV-05 subsection present |
| INV-06 | Plan 01 | No cross-player roll manipulation | SATISFIED | §1 INV-06 subsection present |
| INV-07 | Plan 01 | No self-roll manipulation via timing | SATISFIED | §1 INV-07 subsection present |
| INV-08 | Plan 01 | Pre-advance-gap burn safety | SATISFIED | §1 INV-08 subsection present |
| INV-09 | Plan 01 | Skipped-advance recovery | SATISFIED | §1 INV-09 subsection present |
| INV-10 | Plan 01 | Per-day supply cap | SATISFIED | §1 INV-10 with `pendingByDay[D].supplySnapshot / 2` citation |
| INV-11 | Plan 01 | Per-(player, day) EV cap | SATISFIED | §1 INV-11 with MAX_DAILY_REDEMPTION_EV = 160 ether citation |
| INV-12 | Plan 01 | gameOver mid-pending safety | SATISFIED | §1 INV-12 with forward-reference to SPEC-04 (a) resolved by Plan 02 |
| SPEC-01 | Plan 02 | DayPending struct shape locked | SATISFIED | REQUIREMENTS.md marks Complete; §2 SPEC-01 has `struct DayPending` verbatim |
| SPEC-02 | Plan 02 | Composite-key + UnresolvedClaim removal | SATISFIED | REQUIREMENTS.md marks Complete; §2 SPEC-02 explicitly removes UnresolvedClaim revert |
| SPEC-03 | Plan 02 | dayToResolve arg on resolveRedemptionPeriod | SATISFIED | REQUIREMENTS.md marks Complete; §2 SPEC-03 cites all 3 call sites; source-verified |
| SPEC-04 | Plan 02 | 4 sub-decisions (a-d) locked | SATISFIED | REQUIREMENTS.md marks Complete; §2 SPEC-04 has sub-locks (a) gracefully-resolve (b) zero-rounded proceeds (c) delete at resolve (d) delete at full-claim |
| SPEC-05 | Plan 02 | 50% supply cap snapshot timing | SATISFIED | REQUIREMENTS.md marks Complete; §2 SPEC-05 locks lazy-init with `supplySnapshot == 0 && burned == 0` condition |
| EDGE-01 | Plan 03 | Pre-advance-gap burn on day D | SATISFIED | §3 EDGE-01 subsection present with all 6 fields |
| EDGE-02 | Plan 03 | Two pending days simultaneously | SATISFIED | §3 EDGE-02 subsection present |
| EDGE-03 | Plan 03 | Single player burns multiple days | SATISFIED | §3 EDGE-03 subsection present |
| EDGE-04 | Plan 03 | Multiple players burn same day | SATISFIED | §3 EDGE-04 subsection present |
| EDGE-05 | Plan 03 | Player claims before advance fires | SATISFIED | §3 EDGE-05 subsection present; NotResolved revert named |
| EDGE-06 | Plan 03 | Skipped advance, long stall | SATISFIED | §3 EDGE-06 subsection present |
| EDGE-07 | Plan 03 | V-184 attack reproduction | SATISFIED | §3 EDGE-07 present with verbatim RNGLOCK-FIXREC §103 5-step attack trace and byte-identical negative assertion |
| EDGE-08 | Plan 03 | Burn → gameOver → claim | SATISFIED | §3 EDGE-08 present; cites SPEC-04 (a) |
| EDGE-09 | Plan 03 | Concurrent claims from N players | SATISFIED | §3 EDGE-09 present |
| EDGE-10 | Plan 03 | Re-entrancy attempt on _payEth | SATISFIED | §3 EDGE-10 present; NoClaim revert cited; cites SPEC-04 (d) |
| EDGE-11 | Plan 03 | Burn during rngLocked window | SATISFIED | §3 EDGE-11 present; BurnsBlockedDuringRng cited |
| EDGE-12 | Plan 03 | Burn during livenessTriggered window | SATISFIED | §3 EDGE-12 present; BurnsBlockedDuringLiveness cited |
| EDGE-13 | Plan 03 | Zero-rounded ethValueOwed | SATISFIED | §3 EDGE-13 present; cites SPEC-04 (b) |
| EDGE-14 | Plan 03 | 50% supply cap edge | SATISFIED | §3 EDGE-14 present; Insufficient revert cited; cites SPEC-05 |
| EDGE-15 | Plan 03 | 160 ETH EV cap edge | SATISFIED | §3 EDGE-15 present; ExceedsDailyRedemptionCap cited |
| EDGE-16 | Plan 03 | Cross-day cap reset | SATISFIED | §3 EDGE-16 present |
| EDGE-17 | Plan 03 | Burn after resolve same wall-clock day | SATISFIED | §3 EDGE-17 present; distinguishes legitimate burn from V-184 attack |
| EDGE-18 | Plan 03 | BURNIE pool insufficient at claim | SATISFIED | §3 EDGE-18 present; _payBurnie fallback chain cited |

**Coverage: 35/35 Phase 304 requirements satisfied.** REQUIREMENTS.md traceability table shows SPEC-01..05 marked Complete with commit hashes; INV-01..12 and EDGE-01..18 marked Pending (correct — primary delivery is Phase 306 TST; Phase 304 provides the documentation).

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| None | — | — | — | No TBD/FIXME/XXX/placeholder markers found. No "by construction" / "trivially safe" claims. No history-narration outside §4 EXCEPTION zone. |

Forbidden lexicon scan results:
- `grep -ic 'by construction\|covered by single\|trivially safe'` across full SPEC = **0** (Plan 05 identified 6 instances at scan-start and reframed each in-place; post-correction result is 0)
- History-narration scan (`previously\|formerly\|used to be\|changed from`) = only line 14 (§0 comment-policy statement quoting the forbidden lexicon to declare it forbidden — this is the authorized meta-reference, not an unauthorized use)
- Placeholder scan (`_To be filled by Plan`) = **0**
- All sections substantive (zero stub headings)

**Zero contract changes confirmed.** `git diff HEAD -- contracts/StakedDegenerusStonk.sol contracts/modules/DegenerusGameAdvanceModule.sol` returns empty. `git status --short contracts/` returns empty. Phase 304 commit graph touches only `.planning/` files.

**Zero test changes confirmed.** `git status --short test/` returns empty.

### Human Verification Required

None. Phase 304 is a documentation phase. All deliverable claims are verifiable by grep and source inspection. No visual rendering, UI behavior, real-time behavior, or external service integration is involved.

### Gaps Summary

No gaps. All 5 must-haves are verified. All 35 requirements covered. The deliverable (304-SPEC.md at 960 lines) passes all structural, content, and source-citation checks.

One observation that is not a gap but is worth noting for the Phase 305 IMPL author: the §5.1 citation manifest documents that the IMPL phase should delete only lines `:758-762` (the if-block body) and preserve `:757` (`uint32 currentPeriod = game.currentDayView();`) since that local variable is consumed downstream at `:796`/`:801`/`:806`. This is the disambiguation documented in §5.1 and Plan 05 SUMMARY — it is a load-bearing input for Phase 305 IMPL, not a gap in Phase 304.

---

_Verified: 2026-05-19T06:00:00Z_
_Verifier: Claude (gsd-verifier)_
