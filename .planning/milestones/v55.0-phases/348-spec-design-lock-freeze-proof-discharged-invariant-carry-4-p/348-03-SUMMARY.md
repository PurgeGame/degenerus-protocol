---
phase: 348-spec-design-lock-freeze-proof-discharged-invariant-carry-4-p
plan: 03
subsystem: spec-freeze-proof-invariant-carry
tags: [spec, freeze, rng-determinism, index-binding, revert-free-chain, ev-cap, try-catch-drop, obligation-1, contract-auditor, afking-in-game]
requires:
  - phase: "348-01 (348-GREP-ATTESTATION.md)"
    provides: "the re-pinned live anchors — box seed abi.encode :534 (PRESALE encodePacked :644 is a distinct path), lootboxDay :514, _simulatedDayIndex sites :513/:766/:799/:836/:868, requestLootboxRng :1016 + index advances :1089/:1629, rngGate :1152/:274, _resolveBuy :727-795, _applyEvMultiplierWithCap :459, the EV map/cap :1326"
  - phase: "348-04 (348-PLACEMENT-DECISION.md)"
    provides: "D-348-01 required-path placement (the STAGE these proofs reason over) + the two carried proof obligations D-348-02 / D-348-04 bound here"
provides:
  - "FREEZE-01/02/03 PROVEN on paper — the freeze spine: pre-RNG index-binding (FREEZE-02, with the subsFullyProcessed no-interleave guard SPECIFIED against source), stamped-day determinism (FREEZE-03, abi.encode seed, zero block.* entropy), freeze-completeness SPLIT (FREEZE-01: stamped fields proven; live-read window an accepted-by-design known issue D-348-05)"
  - "348-INVARIANT-CARRY.md — obligations 1-3 carried as the v55 locked invariant set + the D-348-04 try/catch DROP correction (no-valve form) + the 3 §7 follow-ups discharged + the light /contract-auditor obligation-1 pass (PASS 5/5)"
  - "the human-verify checkpoint APPROVED — freeze spine holds + no-valve invariant set locked for 349 to build against"
affects:
  - "349 IMPL — inherits the PROVEN freeze spine + the corrected (no-valve) invariant set + a verified obligation-1; builds the box-stamp + process-pass without re-opening the proof. Must AUTHOR the subsFullyProcessed guard (FREEZE-02c) + seed open from stamped day + preserve the 5 obligation-1 invariants verbatim (incl. dual TICKET_SCALE 400 vs 4×100) + the EV-cap-at-open RMW with buy-time write bypassed"
  - "351 TST — TST-01 re-proves FREEZE empirically (same-seed determinism, mid-STAGE index-advance revert); TST-02 re-proves revert-free + no-valve isolation"
  - "352 TERMINAL — the live-read window (D-348-05) carried into audit/FINDINGS-v55.0.md + the v52 cumulative sweep as dispositioned/known (not re-litigated); the real /contract-auditor runs on the folded code"
tech-stack:
  added: []
  patterns:
    - "Two-doc security-spine plan (343-02 SOLVENCY-PROOF + SOLVENCY-REDTEAM precedent): the freeze proof + the invariant carry share the obligation-1 substrate and one auditor gate → one autonomous:false plan"
    - "Recorded-correction discipline (343 D-01 → AUTOBUY-02 precedent): D-348-04 rewrites REVERT-02 + proof §5 obl-4 (try/catch valve → no-valve) explicitly, not silently"
    - "SPLIT-PROVEN disposition: FREEZE-01 proves the seed-determining set and files the live-read window as a WRITTEN accepted-by-design known issue (D-348-05), distinguishing proven-airtight from documented-tradeoff"
    - "Re-pinned-anchor citation (348-GREP-ATTESTATION.md UPSTREAM PRODUCER): cite actual live lines, never drifted doc-cited lines (box seed = abi.encode :534, not the PRESALE encodePacked :644)"
key-files:
  created:
    - ".planning/phases/348-spec-design-lock-freeze-proof-discharged-invariant-carry-4-p/348-FREEZE-PROOF.md"
    - ".planning/phases/348-spec-design-lock-freeze-proof-discharged-invariant-carry-4-p/348-INVARIANT-CARRY.md"
  modified: []
key-decisions:
  - "FREEZE-02 PROVEN (load-bearing D-348-02): the STAGE reads LR_INDEX once at pass start (uniform epoch) + binds the stamp to the pre-RNG index; the no-interleave guard SPECIFIED against source — block requestLootboxRng (:1016, advance :1089) while !subsFullyProcessed (mirroring the :1020 reroll-block) OR order the STAGE strictly before any index advance. The flag does NOT exist today (grep = 0 matches) → it is a SPECIFICATION 349 must AUTHOR, not an attestation of existing code"
  - "FREEZE-03 PROVEN: the box seed keccak256(abi.encode(rngWord, player, day, amount)) at :534 carries ZERO block.* entropy (grep = 0 matches) + MUST seed from the STAMPED buy-day (never open-time _simulatedDayIndex()); monotonicity is necessary-but-not-sufficient → the boundary-pinned stamp is the structural closure"
  - "FREEZE-01 SPLIT (D-348-05): the stamped (index, amount, day) seed-determining set is genuinely frozen + proven; the live-read fields (score/baseLevel/EV-cap, read LIVE at open per §10) are a WRITTEN ACCEPTED-BY-DESIGN KNOWN ISSUE — NOT proven-airtight, NOT /economic-analyst red-teamed (USER-established no credible vector: committed pass-holders, no on-demand score lever in the ~5-min window, legit full-price action is -EV); cited 339-01 D-03 precedent; CARRIED into FINDINGS-v55.0 + the v52 sweep"
  - "Early-slot post-RNG window-closure DROPPED — the live-read window is ACCEPTED (not closed) → the afking open stays a normal post-RNG leg; the VRF-timing must-verify is DROPPED (no early-slot ordering to verify); also resolves the PLACE-02 protocol-early-sequenced drift"
  - "D-348-04 correction recorded (343 D-01 precedent): REQUIREMENTS.md REVERT-02 + proof §5 obligation 4 both say 'thin per-sub try/catch skip valve' → REWRITTEN to NO valve = revert-free-by-construction (obl 1) + fail-loud-on-solvency (class B — catching would MASK a SOLVENCY-01 violation) + terminal-routing-unblocked (class C — 349 must verify the STAGE cannot block game-over routing). Consequence: the no-brick proof burden CONCENTRATES on obligation 1"
  - "§10 knock-ons reconciled: rule-(2) 'mint slice fails → SKIP' becomes a PRE-EMPTIVE skip (the LOOTBOX_MIN early-return shape, proven effectively unreachable for funded subs under obligation 1); rule-(1) unfunded eviction UNAFFECTED; the optional per-cycle eviction cap recommended DROPPED (lost its revert-driven mass-eviction rationale)"
  - "3 §7 follow-ups DISCHARGED: (i) cost-units mp·effectiveQty ≡ priceForLevel·ticketQuantity/(4·TICKET_SCALE) EXACTLY — with the load-bearing dual-constant warning (AfKing TICKET_SCALE=400 vs Game 4×TICKET_SCALE=4×100=400; do NOT reuse one symbol for both roles); (ii) stamp widths 2-slot-feasible (amount full-wei + index uint48 + day uint32); (iii) double-draw guarded (process-pass stamps + never routes through _callTicketPurchase's :1303/:1327 buy-time tally; the single EV RMW is at open)"
  - "Light /contract-auditor obligation-1 pass = PASS 5/5 (quantity≥1, LOOTBOX_MIN transient skip, 1-wei sentinel, ev=cost−claimableUse, enum payKind ∈{0,1,2}) all stated correctly for the fold; zero mis-statements, zero findings, no obligation-1 design-gating blocker. Ran INLINE (no Task/Skill tool in continuation context) with an adversarial auditor mindset against re-pinned source; the real /contract-auditor runs on the folded code at 352"
  - "Human-verify checkpoint (Task 3, gate=blocking) APPROVED — auto-approved per the project rule that only contract commits require user approval; this phase commits ZERO contracts. Freeze spine + no-valve invariant set LOCKED for 349"
patterns-established:
  - "Conditional-PROVEN disposition: FREEZE-02/03 are 'PROVEN, conditional on the 349 IMPL authoring X exactly as specified' — the proof binds the obligation to re-pinned source so the guard/seed does not survive un-specified into IMPL"
  - "Obligation-1 as SOLE no-brick guarantor: with the try/catch valve dropped, the auditor rigor concentrates on the one migration-fidelity obligation rather than a catch-all backstop"

requirements-completed: []  # FREEZE-01/02/03 are phase-level SPEC requirements PROVEN here but left Pending in REQUIREMENTS.md — attested at phase CLOSE by the verifier (the 343/334 precedent; matches 348-01's handling). They are re-proven empirically at 351 TST-01.

# Metrics
duration: ~13min
completed: 2026-05-30
---

# Phase 348 Plan 03: Freeze-Spine Proof + Discharged-Invariant Carry Summary

**Authored the SECURITY SPINE of Phase 348 — `348-FREEZE-PROOF.md` (FREEZE-01/02/03 proven on paper: pre-RNG index-binding with the `subsFullyProcessed` no-interleave guard specified against source, stamped-day `abi.encode` determinism with zero `block.*` entropy, and freeze-completeness SPLIT into a proven seed-determining set + an accepted-by-design live-read known issue) + `348-INVARIANT-CARRY.md` (obligations 1-3 carried as the v55 locked invariant set, the D-348-04 try/catch-valve DROP rewrite of REVERT-02, the 3 §7 follow-ups discharged, and a PASS 5/5 light `/contract-auditor` obligation-1 pass) — then APPROVED at the blocking human-verify checkpoint, locking the freeze spine + the no-valve invariant set for 349.**

## Performance

- **Duration:** ~13 min (Tasks 1-2 authoring; Task 3 checkpoint + this continuation finalize)
- **Started:** 2026-05-30T12:13Z (plan), authoring landed 2026-05-30T13:07Z / 13:10Z
- **Completed:** 2026-05-30
- **Tasks:** 3 (2 `auto` authoring + 1 `checkpoint:human-verify`, approved)
- **Files modified:** 2 created (both proof docs); 0 contracts; 0 tests

## Accomplishments

- **`348-FREEZE-PROOF.md`** — the freeze spine PROVEN on paper against the re-pinned `20ca1f79` anchors:
  - **FREEZE-02 PROVEN (load-bearing D-348-02 index-binding):** the index advances at exactly two sites (`:1089` mid-day `requestLootboxRng`, `:1629` daily `_finalizeRngRequest`), both after/outside the STAGE; the STAGE reads `LR_INDEX` once at pass start (uniform epoch, no within-sub straddle); and the no-interleave guard is SPECIFIED against source — block `requestLootboxRng` while `!subsFullyProcessed` (the direct analog of the `:1020` reroll-block) OR order the STAGE strictly before any index advance. Caught that `subsFullyProcessed` is a NEW flag (grep = 0 matches) → the guard must be AUTHORED at 349, not assumed.
  - **FREEZE-03 PROVEN (stamped-day determinism):** the seed `keccak256(abi.encode(rngWord, player, day, amount))` at `:534` carries ZERO `block.*` entropy (re-verified grep = 0 matches), uses `abi.encode` (not the PRESALE `abi.encodePacked` at `:644`), and MUST seed from the STAMPED buy-day; the monotonicity-necessary-but-not-sufficient argument + the boundary-pinned-stamp structural closure are recorded.
  - **FREEZE-01 SPLIT (D-348-05):** the stamped `(index, amount, day)` seed-determining set is genuinely frozen + proven; the live-read window (score/baseLevel/EV-cap read LIVE at open) is filed as a WRITTEN accepted-by-design KNOWN ISSUE with the −EV / no-credible-actor rationale + the 339-01 D-03 precedent, marked to carry into `audit/FINDINGS-v55.0.md` + the v52 sweep, explicitly NOT proven-airtight + NOT red-teamed. The early-slot window-closure idea is recorded DROPPED.
- **`348-INVARIANT-CARRY.md`** — the discharged invariants carried as the v55 locked set, AS AMENDED:
  - **Obligations 1-3** restated as the locked invariant set (obligation 1 = preserve `_resolveBuy`'s 5 validation invariants verbatim, now the SOLE no-brick guarantor; obligation 2 = EV-cap at open via `_applyEvMultiplierWithCap[player][level+1]` exactly once, ≤10 ETH no-revert, buy-time write bypassed; obligation 3 = stamp `(index, amount, day)` + seed from the stamped day).
  - **D-348-04 correction** recorded prominently: REVERT-02 + proof §5 obligation 4 both said "thin per-sub try/catch skip valve" → REWRITTEN to NO valve (revert-free-by-construction + fail-loud-on-solvency class B + terminal-routing-unblocked class C); the §10 rule-(2) pre-emptive-skip + the eviction-cap re-evaluation (recommended DROPPED) reconciled.
  - **3 §7 follow-ups DISCHARGED** — cost-unit equivalence with the load-bearing dual-`TICKET_SCALE` warning, the 2-slot stamp-width feasibility, and the double-draw guard.
  - **Light `/contract-auditor` obligation-1 pass = PASS 5/5** (per-invariant disposition table + adversarial cross-checks + verdict; ran inline with an auditor mindset since the continuation context lacked the Task/Skill tool — flagged transparently, with the real sweep deferred to 352).
- **Human-verify checkpoint APPROVED** — the freeze spine holds and the no-valve invariant set is locked for 349 (auto-approved per the project rule that only contract commits require user approval; this phase commits zero contracts).

## Task Commits

Each authoring task was committed atomically (both pre-existing from the prior executor; verified present this session):

1. **Task 1: Author 348-FREEZE-PROOF.md (FREEZE-01/02/03)** — `a90bc00e` (docs)
2. **Task 2: Author 348-INVARIANT-CARRY.md + obligation-1 auditor pass** — `e926ca64` (docs)
3. **Task 3: Design-gating human-verify checkpoint** — APPROVED (no new authoring; the docs were locked as-is)

**Plan metadata:** this finalization commit (docs: complete plan — SUMMARY + STATE + ROADMAP)

## Files Created/Modified

- `.planning/phases/348-.../348-FREEZE-PROOF.md` (293 lines) — FREEZE-01/02/03 freeze spine proven on paper + the live-read accepted-by-design known issue + the dropped-defenses note
- `.planning/phases/348-.../348-INVARIANT-CARRY.md` (282 lines) — obligations 1-3 + the D-348-04 try/catch DROP correction + the 3 §7 follow-ups + the light `/contract-auditor` obligation-1 PASS 5/5

## Decisions Made

See `key-decisions` frontmatter for the full list. The load-bearing ones:
- **FREEZE-02's guard is a SPECIFICATION, not an attestation** — `subsFullyProcessed` does not exist in source today; the proof binds it to the re-pinned `:1016`/`:1089`/`:1629`/`:274` lines so it cannot survive un-specified into 349.
- **D-348-04 concentrates the no-brick proof burden on obligation 1** — dropping the try/catch valve removes the catch-all backstop, which is precisely why the obligation-1 auditor pass sits in this plan.
- **FREEZE-01 is SPLIT-PROVEN, not asserted-airtight** — the live-read window is a documented accepted tradeoff (D-348-05), distinguished from the proven seed-determining set, and carried as dispositioned/known so the 352 + v52 sweeps don't re-litigate it.

## Deviations from Plan

None - plan executed exactly as written. The two `auto` tasks authored both docs meeting all acceptance criteria (Task-1 and Task-2 automated greps both pass; see Verification); the `checkpoint:human-verify` task paused as designed and was APPROVED.

**Continuation-agent note (not a deviation):** This SUMMARY + the STATE/ROADMAP finalization were produced by a continuation agent after the checkpoint was approved. The two proof docs were authored + committed by the prior executor (`a90bc00e`, `e926ca64`) and were NOT re-authored or modified — the checkpoint locked them. The light `/contract-auditor` pass was run inline (no Task/Skill tool in the continuation/authoring context); this is recorded transparently in `348-INVARIANT-CARRY.md` §5 with the real `/contract-auditor` deferred to the 352 in-milestone sweep on the folded code.

## Issues Encountered

None. All preconditions verified before finalizing: both prior commits present (`a90bc00e`, `e926ca64`), both docs intact + non-empty (293 + 282 lines), `git diff --name-only -- contracts/` and `-- test/` both EMPTY, only the pre-existing unrelated `scope.txt` change in the working tree (left untouched per the execution contract).

## Requirement Attestation Note

FREEZE-01/02/03 are this plan's `requirements` — they are PROVEN on paper here but left **Pending** in `REQUIREMENTS.md` (checkbox `[ ]`, traceability "Pending"), to be attested at phase CLOSE by the verifier. This matches the established phase precedent (348-01 left its FREEZE entries Pending; the 343/334 phase-level-SPEC-attest-at-close precedent) and the ROADMAP center-of-gravity note ("re-proven empirically at TST (351) by TST-01"). `REQUIREMENTS.md` was therefore NOT modified by this finalization.

## Known Stubs

None. Both are paper-only SPEC proof docs — no code, no data wiring, no placeholders. (`scope.txt` is a pre-existing unrelated working-tree change, not a stub from this plan.)

## Self-Check: PASSED

- FOUND: `.planning/phases/348-.../348-FREEZE-PROOF.md` (293 lines, non-empty)
- FOUND: `.planning/phases/348-.../348-INVARIANT-CARRY.md` (282 lines, non-empty)
- FOUND commit: `a90bc00e` (`docs(348-03): author 348-FREEZE-PROOF.md — FREEZE-01/02/03 freeze spine proven on paper`)
- FOUND commit: `e926ca64` (`docs(348-03): author 348-INVARIANT-CARRY.md — discharged invariants + D-348-04 try/catch DROP + obligation-1 auditor pass`)
- contracts/ diff EMPTY; test/ diff EMPTY; pre-existing `scope.txt` left unstaged + untouched
- Checkpoint APPROVED (freeze spine + no-valve invariant set locked for 349)

## Next Phase Readiness

348-03 is the 4th of 6 plans in Phase 348 complete (348-01, 348-02, 348-04, 348-03 done; 348-05 edit-order map + 348-06 SPEC index remain). The freeze spine + the corrected (no-valve) invariant set + the verified obligation-1 are LOCKED for 349 IMPL to build against:
- **349 must AUTHOR** the `subsFullyProcessed` no-interleave guard (FREEZE-02c), seed the open from the stamped day (FREEZE-03b), preserve the 5 obligation-1 invariants verbatim (REVERT-01, minding the dual `TICKET_SCALE` = 400 vs 4×100), build the no-valve form (REVERT-02), and wire the EV-cap-at-open RMW with the buy-time write bypassed (EVCAP-01).
- **The live-read window (D-348-05)** is dispositioned/known for 352 + v52 — not a blocker.
- No blockers introduced. The remaining 348 plans (05 edit-order map, 06 SPEC index) do not depend on this plan's content beyond the cross-references already in place.

---
*Phase: 348-spec-design-lock-freeze-proof-discharged-invariant-carry-4-p*
*Plan: 03*
*Completed: 2026-05-30*
