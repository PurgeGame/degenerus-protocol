---
phase: 304-spec-invariant-model-spec
plan: 03
subsystem: sStonk redemption refactor SPEC
tags: [SPEC, EDGE, sStonk, redemption, v44.0, edge-enumeration, V-184-reproduction]
requires: [INV-01, INV-02, INV-03, INV-04, INV-05, INV-06, INV-07, INV-08, INV-09, INV-10, INV-11, INV-12, SPEC-01, SPEC-02, SPEC-03, SPEC-04, SPEC-05]
provides: [EDGE-01, EDGE-02, EDGE-03, EDGE-04, EDGE-05, EDGE-06, EDGE-07, EDGE-08, EDGE-09, EDGE-10, EDGE-11, EDGE-12, EDGE-13, EDGE-14, EDGE-15, EDGE-16, EDGE-17, EDGE-18]
affects: [.planning/phases/304-spec-invariant-model-spec/304-SPEC.md]
tech-stack:
  added: []
  patterns: [edge-case-narrative-spec, positive-negative-assertion-pair, foundry-fuzz-function-prefigured-naming]
key-files:
  created:
    - .planning/phases/304-spec-invariant-model-spec/304-03-SUMMARY.md
  modified:
    - .planning/phases/304-spec-invariant-model-spec/304-SPEC.md
    - .planning/STATE.md
    - .planning/ROADMAP.md
    - .planning/REQUIREMENTS.md
decisions:
  - "EDGE-07 V-184 closure proven STRUCTURALLY by storage-shape (every day's resolve writes a distinct mapping slot + dayToResolve is oldest-first AdvanceModule-bounded); negative assertion is byte-identity of redemptionPeriods[D].roll across all attack-sequence checkpoints"
  - "EDGE-17 distinguishes legitimate-late-day-burn from V-184 ATTACK by demonstrating BOTH outcomes are safe under post-refactor (no overwrite reachable in EITHER case)"
  - "§3 line range fixed for Plan 05 citation-manifest sweep: 401-674"
  - "§1↔§3 cross-link coverage: every INV-01..12 has ≥1 EDGE exerciser (12 rows)"
metrics:
  duration: "~40 min"
  completed: "2026-05-19"
  tasks_completed: 1
  files_created: 1
  files_modified: 4
---

# Phase 304 Plan 03: §3 EDGE-01..18 Exhaustive Scenario Enumeration — Summary

Filled `## §3 — Edge Scenario Enumeration (EDGE-01..18)` with 18 narrative scenario entries (each with Scenario + Positive assertion + Negative assertion + Tests INV-NN + Depends on SPEC-NN + Foundry function name) + a §1↔§3 cross-link coverage table closing the section. EDGE-07 is the V-184 attack reproduction — the headline negative test for v44.0 closure — proving HANDOFF-111..117 are closed STRUCTURALLY by the post-refactor storage shape (RNGLOCK-FIXREC §103 mechanic verbatim). Phase 306 mechanizes each EDGE-NN into the corresponding `testFuzz_EDGE_NN_*` function in `test/fuzz/RedemptionEdgeCases.t.sol` (TST-03) and the V-184 standalone reproduction in TST-04, plus the `vm.skip(HANDOFF-111..117)` 7-block strict-assertion flip in `test/fuzz/RngLockDeterminism.t.sol` (TST-05).

## What was built

### Task 1 — §3 EDGE-01..18 narrative scenario enumeration (commit `315280b0`)

Replaced the `_To be filled by Plan 03_` placeholder under `## §3 — Edge Scenario Enumeration (EDGE-01..18)` with:

**§3 preamble (1 paragraph):** Frames §3 as the v44.0 threat-enumeration locus per Phase 304 threat-model note; states the six labeled sub-fields each EDGE-NN entry carries; names EDGE-07 as the headline negative test that closes HANDOFF-111..117 STRUCTURALLY by absence of the overwrite primitive (per §2.0 Priority Statement clause 1); calls out the §1↔§3 cross-link table at section end as the Plan 05 grep-verifiable coverage manifest.

**18 EDGE-NN subsections, each with 6 labeled sub-fields:**

| # | EDGE-NN | Short name | Headline mechanic | INV-NN tested | SPEC-NN dep |
|---|---------|------------|-------------------|---------------|-------------|
| 1 | EDGE-01 | Pre-advance-gap burn on day D | burn lands in pendingByDay[D], NOT pendingByDay[D-1] | INV-08, INV-04, INV-05 | SPEC-01 + SPEC-03 |
| 2 | EDGE-02 | Two pending days simultaneously | day-D advance resolves D-1 only; pendingByDay[D] byte-identical | INV-08, INV-09 | SPEC-03 + SPEC-04 (c) |
| 3 | EDGE-03 | Single player burns multiple days, never claims | composite-key keeps each (player, day) slot independent | INV-04, INV-07 | SPEC-02 |
| 4 | EDGE-04 | Multiple players burn same day, different times rel. advance | both lands in pendingByDay[D]; same R_{D+1} | INV-04, INV-05, INV-06 | SPEC-01 + SPEC-02 |
| 5 | EDGE-05 | Player claims before advance fires | revert NotResolved | INV-07 | SPEC-02 |
| 6 | EDGE-06 | Skipped advance, long stall | eventual advance resolves day D with VRF word or retryLootboxRng failsafe | INV-09, INV-07 | SPEC-03 |
| 7 | EDGE-07 | **V-184 ATTACK REPRODUCTION (THE HEADLINE)** | same-day post-resolve re-burn → next-advance overwrite — STRUCTURALLY CLOSED | INV-01, INV-06, INV-07 | SPEC-01 + SPEC-03 + SPEC-04 (c) |
| 8 | EDGE-08 | Burn → gameOver → claim | gracefully-resolve under both timing variants | INV-12 | SPEC-04 (a) |
| 9 | EDGE-09 | Concurrent claims from N players same day | aggregate payouts sum to (ethBase * R) / 100 ± (N-1)-wei dust | INV-02, INV-05 | SPEC-02 + SPEC-04 (d) |
| 10 | EDGE-10 | Re-entrancy attempt on _payEth | delete-at-claim fires before _payEth, re-entry hits NoClaim | INV-02, INV-07 | SPEC-04 (d) |
| 11 | EDGE-11 | Burn during rngLocked window | revert BurnsBlockedDuringRng | INV-06 | SPEC-01 (preserves :492 guard) |
| 12 | EDGE-12 | Burn during livenessTriggered window | revert BurnsBlockedDuringLiveness | INV-08 | SPEC-01 (preserves :491 guard) |
| 13 | EDGE-13 | Zero-rounded ethValueOwed from tiny burn | burn proceeds; zero-claim is no-op | INV-04 | SPEC-04 (b) |
| 14 | EDGE-14 | 50% supply cap edge | exact-cap succeeds, +1-wei reverts Insufficient; lazy-init snapshot immutable rest of day | INV-10 | SPEC-05 |
| 15 | EDGE-15 | 160 ETH EV cap edge | exact-cap succeeds, +1-wei reverts ExceedsDailyRedemptionCap | INV-11 | SPEC-02 |
| 16 | EDGE-16 | Cross-day cap reset | composite-key makes reset structural | INV-11 | SPEC-02 |
| 17 | EDGE-17 | Burn after resolve same wall-clock day (legitimate) | distinct from V-184: both legitimate-late-day-burn AND attack-attempt are SAFE under post-refactor | INV-01, INV-04, INV-08 | SPEC-01 + SPEC-03 + SPEC-04 (c) |
| 18 | EDGE-18 | BURNIE pool insufficient at claim | _payBurnie fallback chain via coinflip.claimCoinflipsForRedemption | INV-03 | SPEC-02 (preserves _payBurnie) |

**§1↔§3 cross-link coverage table (end of §3):** 12 rows, one per INV-NN, listing the EDGE-NN exercisers for each. Every INV-01..12 has at least one EDGE-NN exerciser; Plan 05 grep-verifies the count and per-INV coverage.

| INV-NN | EDGE-NN exercisers |
|--------|---------------------|
| INV-01 | EDGE-07 + EDGE-17 |
| INV-02 | EDGE-09 + EDGE-10 |
| INV-03 | EDGE-18 |
| INV-04 | EDGE-03 + EDGE-04 + EDGE-13 + EDGE-17 |
| INV-05 | EDGE-01 + EDGE-04 + EDGE-09 |
| INV-06 | EDGE-04 + EDGE-07 + EDGE-11 |
| INV-07 | EDGE-03 + EDGE-05 + EDGE-06 + EDGE-07 + EDGE-10 |
| INV-08 | EDGE-01 + EDGE-02 + EDGE-12 + EDGE-17 |
| INV-09 | EDGE-02 + EDGE-06 |
| INV-10 | EDGE-14 |
| INV-11 | EDGE-15 + EDGE-16 |
| INV-12 | EDGE-08 |

## EDGE-NN entries that triggered the deepest design-intent expansion (Plan 04 should revisit)

The plan asked which EDGE-NN entries surfaced the most design-intent depth — for Plan 04 to verify the §4 design-intent walk and game-theory analysis fully cover the case-space:

1. **EDGE-07 (V-184 attack reproduction):** the headline negative test. Three derivative cases at trace step (5) of the EDGE-07 Scenario field were enumerated: (i) re-burn lands in `pendingByDay[D]` (still day D wall-clock, post-resolve, pre-day-boundary), (ii) re-burn lands in `pendingByDay[D+1]` (wall-clock crossed), and the structural argument that NO future advance writes to `redemptionPeriods[D]` because (a) the day-`D` resolve at step 2 is one-shot via SPEC-03 `dayToResolve = D` only being passed once and (b) AdvanceModule's catch-up loop iterates oldest-first so subsequent advances pass strictly increasing `dayToResolve` values. Plan 04 should walk the design intent of removing `redemptionPeriodIndex` against the V-184 attack chain verbatim and confirm the post-refactor storage shape forecloses ALL trace variants. The "no future advance passes `dayToResolve = D` after the day-`D+1` advance" claim is load-bearing — Plan 05 should grep-verify the AdvanceModule call sites at `:1230`, `:1293`, `:1323` each compute `dayToResolve` from a local-variable that monotonically advances by day (no rollback path).

2. **EDGE-17 (burn after resolve same wall-clock day — legitimate):** distinguishing the legitimate-late-day-burn from the V-184 ATTACK was the deepest case-disambiguation in §3. Both produce write-once outcomes; the difference is intent (legitimate burn vs attack-attempt re-burn), but the post-refactor structural property is identical: no overwrite reachable in EITHER case. Plan 04's design-intent walk of removing `redemptionPeriodIndex` (deletion item 1) should explicitly note that the post-refactor shape collapses the two cases into a single safe outcome — closing the V-184 attack class WHILE preserving the legitimate-late-day-burn path that the pre-refactor design likely intended.

3. **EDGE-14 (50% supply cap edge):** Sub-scenario 3 — the lazy-init immutability across same-day burns — exercises SPEC-05's "snapshot immutable rest of day" property at the boundary. The pre-refactor `:758-762` reset block already lazy-inited on a per-period basis; SPEC-05 preserves that semantic verbatim under per-day keying with the predicate changing from "period changed" to "slot reads zero." Plan 04 design-intent walk of deletion item 7 (the `redemptionPeriodIndex` reset block at `:757-762`) should explicitly note that the reset block's lazy-init behavior is preserved structurally — it is not deleted in the behavioral sense, only re-expressed as the slot-zero predicate under the per-day mapping shape.

4. **EDGE-10 (re-entrancy on _payEth):** the CEI ordering at the existing `:618-684` is load-bearing for the negative assertion. SPEC-04 (d) `delete pendingRedemptions[msg.sender][day]` MUST fire before the external `_payEth` `.call`. The §3 entry reads from the existing source: the delete fires at `:660-661` (inside the `flipResolved == true` branch), then `_payBurnie` at `:677`, then emit at `:680`, then `_payEth` at `:683`. Plan 04 design-intent walk of deletion item 6 (`UnresolvedClaim` revert) should NOT alter the CEI ordering — and Plan 05 should grep-verify the IMPL phase's diff preserves the relative ordering at the post-refactor line numbers (the `delete` site MUST be BEFORE the `_payEth` site, not after — re-entrancy safety depends on it).

## Cross-cutting design-intent notes surfaced during EDGE authoring

Two minor observations surfaced during authoring that may inform Plan 04 design-intent walk:

- **EDGE-07's "no future advance writes `dayToResolve = D`" claim is structurally true under SPEC-03 oldest-first ordering, but the proof depends on the AdvanceModule's catch-up loop semantics.** The §3 entry asserts this; Plan 04 should walk the design-intent of the SPEC-03 oldest-first lock (the secondary lock at SPEC-03 line 351 of 304-SPEC.md) and confirm the AdvanceModule iteration is monotonically forward by day — no rollback, no reset to earlier day. If a future AdvanceModule change introduced a rollback path (e.g., re-execute a day's advance on an admin-triggered reset), EDGE-07's structural argument would weaken. Note: per `feedback_frozen_contracts_no_future_proofing.md`, contracts are frozen at deploy, so this is a closure-time check only — not a future-extensibility concern.

- **EDGE-08 (gameOver mid-pending) Variant 1 specifically relies on the SPEC-04 (a) lock (gracefully-resolve).** The §1 INV-12 forward-reference to SPEC-04 (a) is resolved at Plan 02; Plan 04 design-intent walk of the SPEC-04 (a) lock should explicitly trace why "gracefully-resolve" was chosen over "fail-closed" — the user-stated security-first posture per §2.0 clause 1 suggests fail-closed is the conservative choice, but SPEC-04 (a) chose gracefully-resolve because the existing `:638-643` 50/50-vs-100% split logic already produces the correct post-gameOver semantic without an explicit new branch. Plan 04 §4 should document this trade-off explicitly so the design-intent rationale is auditable.

## §3 line range (for Plan 05 citation-manifest sweep)

`§3 — Edge Scenario Enumeration (EDGE-01..18)` occupies **lines 401-674** of `304-SPEC.md` (273 lines). Plan 05 grep-verifies every contract `:line` cited within this range against `contracts/StakedDegenerusStonk.sol` HEAD `MILESTONE_V43_AT_HEAD_8111cfc5189f628b64b500c881f9995c3edf0ed2`.

Cited contract surfaces in §3 that Plan 05 must source-verify (subset of those already in §1/§2 — Plan 05 cross-checks for consistency):

- `StakedDegenerusStonk.sol` errors at `:88-117`: `Unauthorized` (`:88`), `Insufficient` (`:91`), `ZeroAddress` (`:94`), `TransferFailed` (`:97`), `BurnsBlockedDuringRng` (`:100`), `BurnsBlockedDuringLiveness` (`:105`), `UnresolvedClaim` (`:108`; removed at IMPL per SPEC-02), `NoClaim` (`:111`), `NotResolved` (`:114`), `ExceedsDailyRedemptionCap` (`:117`).
- `StakedDegenerusStonk.sol` burn guards: `:491` (livenessTriggered guard, EDGE-12), `:492` (rngLocked guard, EDGE-11).
- `StakedDegenerusStonk.sol` claim/resolve sites: `:624` (NotResolved revert preserved per SPEC-02, EDGE-05), `:632` (totalRolledEth floor-division, EDGE-09 dust accumulation), `:635` (isGameOver check, EDGE-08), `:638-643` (50/50 split vs 100% direct, EDGE-08), `:649-654` (coinflip oracle read, EDGE-18), `:657` (pendingRedemptionEthValue decrement, EDGE-09/10), `:660-661` (delete pendingRedemptions at full-claim, EDGE-10), `:683` (_payEth at CEI tail, EDGE-10), `:818` (_payEth amount==0 early return, EDGE-13).
- `StakedDegenerusStonk.sol` burn site: `:754` (amount==0 revert, EDGE-13), `:763` (50% supply cap check, EDGE-14), `:801` (160 ETH EV cap check, EDGE-15), `:803` (claim.ethValueOwed += assignment ordering, EDGE-15), `:842-852` (`_payBurnie` fallback chain, EDGE-18).
- `StakedDegenerusStonk.sol` constant: `MAX_DAILY_REDEMPTION_EV = 160 ether` at the constants block (analog of `:254` per §1 SUMMARY).

## Foundry function-name registry (for Phase 306 TST-03 file `test/fuzz/RedemptionEdgeCases.t.sol`)

Each EDGE-NN has a suggested `testFuzz_EDGE_NN_*` name in its entry. Phase 306 may rename if desired; the names below are the recommended starting point and preserve the EDGE-NN → fuzz-function mapping required by REQUIREMENTS.md TST-03:

- `testFuzz_EDGE_01_PreAdvanceGapBurnLandsInCurrentDayPool`
- `testFuzz_EDGE_02_TwoPendingDaysSimultaneous`
- `testFuzz_EDGE_03_SinglePlayerMultiDayClaimsIndependent`
- `testFuzz_EDGE_04_MultiplePlayersSameDay`
- `testFuzz_EDGE_05_ClaimBeforeResolveReverts`
- `testFuzz_EDGE_06_SkippedAdvanceLongStallEventualResolution`
- `testFuzz_EDGE_07_V184AttackReproductionStructuralClosure` (also feeds TST-04 standalone reproduction + TST-05 `vm.skip(HANDOFF-111..117)` strict-assertion flip)
- `testFuzz_EDGE_08_BurnGameOverClaimBothVariants`
- `testFuzz_EDGE_09_NPlayersConcurrentClaimsSumWithDust`
- `testFuzz_EDGE_10_ReentrancyOnPayEthBlocked`
- `testFuzz_EDGE_11_BurnDuringRngLockedReverts`
- `testFuzz_EDGE_12_BurnDuringLivenessReverts`
- `testFuzz_EDGE_13_ZeroRoundedEthValueOwedBurnProceeds`
- `testFuzz_EDGE_14_SupplyCapExactOneWeiOverAndLazyInit`
- `testFuzz_EDGE_15_EvCapExactOneWeiOver`
- `testFuzz_EDGE_16_CrossDayCapResetStructural`
- `testFuzz_EDGE_17_LateDayBurnPostResolveLegitimate`
- `testFuzz_EDGE_18_BurniePoolInsufficientFallback`

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] EDGE-17 day-naming inconsistency + history-narration phrase**
- **Found during:** Task 1 self-check
- **Issue:** First draft of EDGE-17 Scenario contained a self-correcting mid-sentence aside ("wait, this requires care...no: the prior day's resolve targeted...") that left the Positive + Negative assertions misaligned with the corrected day-naming. Also contained "previously-written rolls" — a history-narration phrase trip per `feedback_no_history_in_comments.md` (§3 must describe what IS post-refactor, never what changed).
- **Fix:** Rewrote EDGE-17 Scenario with a clean forward-flowing trace: day-`D` advance at 22:58 writes `redemptionPeriods[D-1].roll = R_D`; 23:30 burn lands in `pendingByDay[D]`; next-day (day-`D+1`) advance writes `redemptionPeriods[D].roll = R_{D+1}`. Reconciled Positive + Negative assertions with the corrected day-naming (the Negative assertion now reads "`redemptionPeriods[D-1].roll` byte-identical to `R_D`" instead of the inconsistent prior "`R_{D+1}`"). Replaced "previously-written rolls" with "any earlier-written rolls."
- **Files modified:** `.planning/phases/304-spec-invariant-model-spec/304-SPEC.md` (3 insertions, 3 deletions in EDGE-17 region)
- **Commit:** `971688ba`

All other plan execution was exactly as written. All eight acceptance criteria pass on first verify (including the post-fix re-verify):

1. `grep -c "^### EDGE-" 304-SPEC.md` returns exactly 18 (verified — 18 EDGE-NN headings).
2. Every EDGE-NN subsection contains all six labeled sub-fields (verified — 18 each of `**Scenario:**`, `**Positive assertion:**`, `**Tests INV-NN:**`, `**Depends on SPEC-NN:**`, `**Foundry function name:**`; 19 `**Negative assertion`-prefixed labels because EDGE-07's strengthening label "Negative assertion (THE LOAD-BEARING V-184 CLOSURE)" matches the regex — this is a non-defect over-match, not a duplicate).
3. EDGE-07 cites V-184 + RNGLOCK-FIXREC §103 + HANDOFF-111..117 (verified — 17 V-184/RNGLOCK-FIXREC-§103/HANDOFF-11[1-7] references across §3, ≥2 required).
4. EDGE-07 negative assertion explicitly states `redemptionPeriods[D].roll` byte-identical to first-write value (verified — line 495 `byte-identical to its first-write value `R_{D+1}`...assertEq enforced at every checkpoint`).
5. EDGE-08 cites SPEC-04 (a) (verified — `Depends on SPEC-04 (a)` in EDGE-08 entry); EDGE-13 cites SPEC-04 (b) (verified — `Depends on SPEC-04 (b)`); EDGE-10 cites SPEC-04 (d) (verified — `Depends on SPEC-04 (d)`); EDGE-14 cites SPEC-05 (verified — `Depends on SPEC-05`).
6. EDGE entries cite valid error names from `StakedDegenerusStonk.sol:88-117`: `NotResolved` (6), `Insufficient` (5), `BurnsBlockedDuringRng` (2), `BurnsBlockedDuringLiveness` (2), `ExceedsDailyRedemptionCap` (3), `NoClaim` (2), `TransferFailed` (2). All valid; no fabricated error names.
7. §1↔§3 cross-link table at end of §3 lists all 12 INV-NN rows with ≥1 EDGE exerciser each (verified — `grep -c "^- INV-0[1-9] ←\|^- INV-1[0-2] ←"` returns 12).
8. Placeholder `_To be filled by Plan 03_` removed (verified — `grep -c "_To be filled by Plan 03_"` returns 0).

## Self-Check: PASSED

- File `.planning/phases/304-spec-invariant-model-spec/304-SPEC.md` exists (FOUND; modified at commit `315280b0`).
- Commit `315280b0` Task 1 §3 fill (FOUND in `git log --oneline -1 -- .planning/phases/304-spec-invariant-model-spec/304-SPEC.md`).
- 18 `### EDGE-NN:` subsections (verified — `grep -c "^### EDGE-"` returns 18).
- All six labeled sub-fields appear 18× each (Scenario, Positive assertion, Tests INV-NN, Depends on SPEC-NN, Foundry function name) — verified by per-label `grep -c`.
- EDGE-07 V-184 mechanic cited verbatim (verified — `byte-identical to its first-write value` + `RNGLOCK-FIXREC §103` + `HANDOFF-111..117` + the step-1..step-5 trace narrative match RNGLOCK-FIXREC §103.A trace).
- EDGE-08 cites SPEC-04 (a); EDGE-13 cites SPEC-04 (b); EDGE-10 cites SPEC-04 (d); EDGE-14 cites SPEC-05 (verified).
- §1↔§3 cross-link table covers all 12 INV-NN (verified — 12 rows; each INV-NN has ≥1 EDGE exerciser).
- §3 spans lines 401-674 (273 lines); §4 (line 676) + §5 (line 680) placeholders intact for Plans 04-05.
- Zero history-narration words (`previously` / `formerly` / `used to be` / `changed from`) in §3 (verified via grep of `previously\|formerly\|used to be\|changed from` returning 0 matches within the §3 line range 401-674).
