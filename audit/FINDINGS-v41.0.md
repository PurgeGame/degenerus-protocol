---
phase: 284-delta-audit-findings-consolidation-terminal
plan: 01
milestone: v41.0
milestone_name: Cross-Call Determinism Fix (mint-batch + hero-override)
audit_baseline: cd549499
audit_baseline_signal: MILESTONE_V40_AT_HEAD_cd549499
v34_baseline: 6b63f6d4daf346a53a1d463790f637308ea8d555
v34_baseline_signal: MILESTONE_V34_AT_HEAD_6b63f6d4daf346a53a1d463790f637308ea8d555
audit_subject_head: "ab76e990"
closure_signal: MILESTONE_V41_AT_HEAD_315978a0c18294e0d7fa5cd4cdfe7f8e5b9a95c4
deliverable: audit/FINDINGS-v41.0.md
requirements: [FIX-01, FIX-02, FIX-03, FIX-04, FIX-05,
               TST-FIX-01, TST-FIX-02, TST-FIX-03, TST-FIX-04, TST-FIX-05, TST-FIX-06,
               SWEEP-01, SWEEP-02, SWEEP-03, SWEEP-04, SWEEP-05, TST-SWEEP-01,
               HOFIX-AUDIT-01, HOFIX-AUDIT-02, HOFIX-AUDIT-03, HOFIX-AUDIT-04, HOFIX-AUDIT-05,
               FIX-HOFIX-01, FIX-HOFIX-SWEEP-NN,
               TST-HOFIX-01, TST-HOFIX-02, TST-HOFIX-03, TST-HOFIX-04, TST-HOFIX-05,
               JPSURF-01, JPSURF-02, JPSURF-03, JPSURF-04, JPSURF-05,
               AUDIT-01, AUDIT-02, AUDIT-03, AUDIT-04, AUDIT-05, AUDIT-06, AUDIT-07, AUDIT-08,
               REG-01, REG-02, REG-03, REG-04]
phase_status: terminal
phase_count: 9
phase_ids: [281, 282, 283, 285, 286, 287, 288, 289, 284]
phase_shape: multi-phase
requirements_total: 43
findings_total: 3
findings_resolved_at_v41: 3
findings_pending_user_remediation: 0
known_issues_disposition: UNMODIFIED
adversarial_pass_skills: [contract-auditor, zero-day-hunter, economic-analyst]
adversarial_pass_pattern: PARALLEL_SINGLE_MESSAGE
adversarial_passes: 2  # original on F-41-01 + Phase 283 hand-forward; re-pass on Phase 288 dailyIdx fix
out_of_scope_skills: [degen-skeptic]
supersedes: none
status: "FINAL — READ-ONLY"
read_only: true
generated_at: 2026-05-17
---

# v41.0 Findings — Cross-Call Determinism Fix (mint-batch + hero-override) (Terminal)

**Audit Baseline.** The audit baseline is v40.0 closure HEAD `cd549499` (closure signal `MILESTONE_V40_AT_HEAD_cd549499` carry-forward from `audit/FINDINGS-v40.0.md` §9c). v41.0 audit-subject HEAD is `ab76e990` (post-Phase-289). v41.0 closure HEAD is resolved at the Phase 284 terminal closure-flip task per D-284-CLOSURE-01 — see §9c for the emitted `MILESTONE_V41_AT_HEAD_315978a0c18294e0d7fa5cd4cdfe7f8e5b9a95c4` signal. The 9-phase wave shape (Phase 281 FIX mint-batch + Phase 282 TST-FIX mint-batch + Phase 283 SWEEP cross-surface batched-loop + Phase 285 HOFIX SUPERSEDED-AT-PHASE-288 + Phase 286 TST-HOFIX REVISED-AT-PHASE-289 + Phase 287 JPSURF flag-only commitment-window audit + Phase 288 FIX-JPSURF dailyIdx structural fix + Phase 289 TST-JPSURF cross-day regression + Phase 284 TERMINAL audit) is structurally COMPLETE. The v41.0 audit subject is the 6-commit source-tree delta `git log cd549499..ab76e990 -- contracts/ test/`: Phase 281 (`221afcf7`) mint-batch determinism fix via owed-salt seed mix (B2 symmetric scope covering both `_raritySymbolBatch` callsites); Phase 282 (`a1212b00`) multi-call drain regression fixture (REDUCED SCOPE — 4 of 6 original TST-FIX requirements landed per user re-scope authorization 2026-05-16); Phase 285 (`c4d62564`) hero-override write-side `+1` offset (SUPERSEDED-AT-PHASE-288 — see §3a/§4 for supersede narrative; bytecode reverted by Phase 288 + canonical semantic restored); Phase 286 (`cef9a972`) hero-override regression fixture (REVISED-AT-PHASE-289 — Phase 286 tests were authored against the Phase 285 `+1` semantic and adjusted by Phase 289 to the post-Phase-288 canonical semantic); Phase 288 (`4837fa5c`) F-41-03 cross-day determinism fix via `dailyIdx` operational read (supersedes Phase 285); Phase 289 (`ab76e990`) cross-day snapshot regression fixture (TST-JPSURF-01..04 + adjustments to Phase 286 TST-HOFIX tests). Phase 283 contributes zero `contracts/` and zero `test/` commits per default zero-mutation SWEEP outcome. Phase 287 contributes zero `contracts/` + zero `test/` commits per FLAG-ONLY user posture. Phase 284 is SOURCE-TREE FROZEN — zero `contracts/` and zero `test/` mutations; only the audit deliverable + planning artifacts + closure-flip docs are committed.

**Scope.** Single canonical milestone-closure deliverable for v41.0 per D-41N-FILES-01 carry of D-40N-FILES-01 / D-274-FILES-01 chain (9-section shape locked). v41.0 = **9-phase multi-phase milestone shape** per `.planning/REQUIREMENTS.md` — Phase 281 (FIX — mint-batch determinism; COMPLETE), Phase 282 (TST-FIX — mint-batch regression; COMPLETE), Phase 283 (SWEEP — cross-surface batched-loop; default zero-mutation; COMPLETE; hand-forward observation surfaced F-41-02), Phase 285 (HOFIX — hero-override day-index fix via write-side `+1`; **SUPERSEDED-AT-PHASE-288**; structurally restored to canonical at Phase 288), Phase 286 (TST-HOFIX — hero-override regression; **REVISED-AT-PHASE-289**), Phase 287 (JPSURF — commitment-window audit FLAG-ONLY posture; 0 VIOLATIONs + F-41-03 candidate surfaced), Phase 288 (FIX-JPSURF — dailyIdx structural fix; F-41-02 + F-41-03 RESOLVED), Phase 289 (TST-JPSURF — cross-day regression coverage; COMPLETE), Phase 284 (TERMINAL — this deliverable; SOURCE-TREE FROZEN). Each contract+test surface phase ran USER-APPROVED batched commits per `feedback_no_contract_commits.md` + `feedback_batch_contract_approval.md` + `feedback_never_preapprove_contracts.md` + `feedback_manual_review_before_push.md`. **First multi-finding milestone in v25..v41 audit history — §4 contains THREE non-zero finding blocks: F-41-01 (mint-batch determinism; HIGH; RESOLVED_AT_V41), F-41-02 (hero-override day-index within-day; HIGH with CRITICAL elevation note on `isFinalPhysicalDay_`; RESOLVED_AT_V41), F-41-03 (hero-override day-index cross-day; MEDIUM-catastrophy-tier; RESOLVED_AT_V41).** Phase 284 is the SOLE terminal phase and is SOURCE-TREE FROZEN — zero `contracts/` and zero `test/` mutations; only `audit/FINDINGS-v41.0.md` + `.planning/phases/284-.../*` + the 5 closure-flip docs (`ROADMAP.md` / `STATE.md` / `MILESTONES.md` / `PROJECT.md` / `REQUIREMENTS.md`) are committed at this phase.

**Write policy.** READ-only after the terminal Phase 284 closure-flip task per D-41N-APPROVAL-01 carry of D-40N-APPROVAL-01 / D-274-APPROVAL-01 chain. KNOWN-ISSUES.md is **UNMODIFIED** at v41 close per D-281-KI-01 (carry from v40 to v41). The §6 closure verdict for KNOWN-ISSUES.md is `KNOWN_ISSUES_UNMODIFIED`. Per `feedback_never_preapprove_contracts.md`, the agent does NOT pre-approve any contract change — every Phase 281 / 282 / 285 / 286 / 288 / 289 contract+test commit landed under a USER-APPROVED batched gate (see Section 9.NN commit-readiness register). Per `feedback_manual_review_before_push.md`, the user reviewed each contract diff before any push. The READ-only flip on `audit/FINDINGS-v41.0.md` (chmod 444 + frontmatter `status: FINAL — READ-ONLY` + `read_only: true`) is the terminal action of the Phase 284 closure-flip task. This phase exercises `feedback_no_history_in_comments.md` (prose describes what IS at v41 close — Phase 285's `+1` write-side fix was a valid intermediate step that Phase 288 structurally supersedes; v41-close state is the Phase 288 canonical semantic), `feedback_rng_backward_trace.md` + `feedback_rng_commitment_window.md` (mandatory methodology for §4 owed-salt + hero-override cross-day surfaces + Phase 287 JPSURF commitment-window audit), and `feedback_gas_worst_case.md` (gas claims rest on Phase 281 theoretical-worst-case derivation `281-01-MEASUREMENT.md` §3a ≤2880 gas across 5840-trait drain; Phase 288 bytecode delta −36 bytes net per `288-01-COMMIT-MESSAGE.md`).

---

## 2. Executive Summary

### Closure Verdict Summary

- **AUDIT-01:** Section 3.A delta-surface table covers every changed declaration across all 6 v41.0 source-tree commits `cd549499` → `ab76e990` with hunk-level evidence + `{NEW, MODIFIED_LOGIC, REFACTOR_ONLY, DELETED, DOCS_ONLY, ANALYTICAL, SUPERSEDED}` classification per row. Six phase row groups (Phase 281, 282, 285 SUPERSEDED, 286 REVISED, 288, 289) + Phase 283 + Phase 287 ANALYTICAL rows + a Phase 284 SOURCE-TREE-FROZEN attestation.
- **AUDIT-02:** Section 4 carries three F-41-NN finding blocks — F-41-01 (mint-batch determinism, HIGH, RESOLVED via Phase 281 owed-salt + Phase 282 algorithm-level tests); F-41-02 (hero-override day-index within-day, HIGH with CRITICAL elevation note for `isFinalPhysicalDay_`, RESOLVED via Phase 288 dailyIdx structural fix + Phase 289 regression coverage; Phase 285 was a valid intermediate fix that Phase 288 supersedes structurally); F-41-03 (hero-override day-index cross-day, MEDIUM-catastrophy-tier, RESOLVED collaterally via Phase 288 dailyIdx fix + Phase 289 TST-JPSURF-04 anchor-replay regression).
- **AUDIT-03:** Section 3.C conservation re-proof: (i) total-traits-credited invariant; (ii) bit-slice independence; (iii) storage byte-identity for non-mutated slots across both fixes; (iv) hero-override `dailyIdx` read-consistency invariant — both CALL 1 and CALL 2 of the 2-call ETH split read `dailyHeroWagers[dailyIdx]` with `dailyIdx` provably frozen across the rng-lock window (single-writer slot, `_unlockRng` is the sole mutator, fires only at end-of-cycle).
- **AUDIT-04:** Section 3.B zero-new-state grep-proof attestation — Phase 281 owed-salt chosen-shape (c) = zero storage delta; Phase 285 `+1` arithmetic-only and SUPERSEDED; Phase 288 reverts Phase 285 byte-for-byte at the bet write site AND adds a `dailyIdx` SLOAD substituting for a `_simulatedDayIndex()` internal call (zero new storage; ZERO bytecode growth — net −36 bytes per `288-01-COMMIT-MESSAGE.md`). ALL fixes attest zero new public/external mutation entry points + zero new admin + zero new modifiers + zero new upgrade hooks. 5-row roll-up matches v36..v40 audit-attestation pattern.
- **AUDIT-05:** Section 4 11-surface v40-carry RE_VERIFIED at v41 + Section 4 v41-new adversarial sweep attested via **TWO** 3-skill PARALLEL adversarial passes per D-271-ADVERSARIAL-01 + D-271-ADVERSARIAL-03 carry. Original pass: ran on the post-Phase-282 finished §4 draft, surfaced Hypothesis (ix) `_applyHeroOverride` cross-day vector → ELEVATED_TO_FINDING F-41-02 by 3-of-3 consensus. RE-PASS: ran on the Phase 288 dailyIdx fix, 0 FINDING_CANDIDATEs across all 3 skills (contract-auditor: 7 hypotheses A..G all SAFE or NEGATIVE_RESULT_ONLY; zero-day-hunter: 14 hypotheses N1..N14 all SAFE/NEGATIVE; economic-analyst: 11 hypotheses E1..E7 + B-04..B-06, 1 INFO-tier E3 launch-comms candidate only). `/degen-skeptic` OUT OF SCOPE per D-271-ADVERSARIAL-02 carry.
- **AUDIT-06:** Section 6 KI walkthrough EXC-01..04 RE_VERIFIED at v41 HEAD; EXC-01/02/03 RE_VERIFIED-NEGATIVE-scope at v41 (the v41 audit subject has zero affiliate-roll / AdvanceModule / gameover-RNG-substitution interaction); EXC-04 STRUCTURALLY ELIMINATED preserved (no `EntropyLib.entropyStep` resurrection at v41 close HEAD; static-analysis grep proof). KNOWN-ISSUES.md UNMODIFIED per D-281-KI-01; Section 6c closure verdict `KNOWN_ISSUES_UNMODIFIED`.
- **AUDIT-07:** Section 9c closure-signal emission completes the v41.0 milestone closure: `3 of 3 F-41-NN RESOLVED_AT_V41; 0 of 0 KI_ELIGIBLE_PROMOTED; KNOWN_ISSUES_UNMODIFIED`.
- **AUDIT-08:** KNOWN-ISSUES.md disposition `D-281-KI-01` locked (UNMODIFIED at v41 close — all three F-41-NN findings are CLOSED-AT-MILESTONE shipped-then-fixed entries that fall outside the unfixed-surviving-defect taxonomy KNOWN-ISSUES.md tracks). Closure verdict `KNOWN_ISSUES_UNMODIFIED`.
- **REG-01:** Section 5a — v40.0 closure signal `MILESTONE_V40_AT_HEAD_cd549499` re-verified NON-WIDENING at v41 HEAD for v40-touched surfaces NOT in v41 scope. LootboxModule Bernoulli + WWXRP consolation + JackpotModule:2216 BAF Bernoulli + `_jackpotTicketRoll` keccak self-mix + `LootBoxOpened`/`BurnieLootOpen`/`JackpotTicketWin` event shapes + whole-BURNIE floors — all byte-identical between v40 close HEAD and v41 close HEAD on non-Mint, non-`_applyHeroOverride`, non-`placeDegeneretteBet` surfaces.
- **REG-02:** Section 5b — v34.0 closure signal `MILESTONE_V34_AT_HEAD_6b63f6d4daf346a53a1d463790f637308ea8d555` re-verified NON-WIDENING at v41 HEAD; TraitUtils + `_pickSoloQuadrant` + JackpotBucketLib byte-identical.
- **REG-03:** Section 5c / Section 6b 4-row KI envelope re-verifications — EXC-01/02/03 RE_VERIFIED-NEGATIVE-scope at v41; EXC-04 STRUCTURALLY ELIMINATED preserved.
- **REG-04:** Section 5d per-finding PASS/SUPERSEDED row table walking `audit/FINDINGS-v25.0.md` to `audit/FINDINGS-v40.0.md` for findings referencing the v41-touched function/surface set (`DegenerusGameMintModule.processFutureTicketBatch` + `_raritySymbolBatch` + `_applyHeroOverride` + `placeDegeneretteBet` + `_resumeDailyEth` + jackpot 2-call ETH split path); each prior finding on these surfaces re-verified RESOLVED or NEGATIVE-scope at v41 close HEAD.

### Severity Counts (per D-08 5-Bucket Rubric)

- CRITICAL: 0 (note: F-41-02 carries a CRITICAL elevation note for `isFinalPhysicalDay_` where `dailyBps == 10_000` — final-day exposure misallocates 100% of remaining `currentPrizePool`; default rubric severity HIGH).
- HIGH: 2 (F-41-01 RESOLVED_AT_V41 + F-41-02 RESOLVED_AT_V41).
- MEDIUM: 1 (F-41-03 catastrophy-tier RESOLVED_AT_V41).
- LOW: 0
- INFO: 0 (1 INFO-tier launch-communication observation E3 from economic-analyst re-pass — hero-override mechanic activation EV — is documented under §9 "Deferred to Future Milestones" as a launch-FAQ item, not as an F-41-NN block).
- Total F-41-NN: 3 (all RESOLVED_AT_V41).

**First multi-finding milestone in v25..v41 audit history.** All three F-41-NN findings shipped at v40.0 closure HEAD `cd549499` and are RESOLVED at v41.0 close. F-41-01 (mint-batch determinism) was realized in production on blocks 10862393..10862412 (20 byte-identical 292-trait `TraitsGenerated` events for the same `(player, idx, owed)` tuple); RESOLVED via Phase 281 owed-salt 4th keccak input (zero new storage). F-41-02 (hero-override within-day) was surfaced by Phase 283 SWEEP-04 hand-forward observation + Phase 284 first-pass 3-skill PARALLEL adversarial consensus; the original CALL-1/CALL-2 same-day vector is closed by Phase 285's write-side `+1` fix; F-41-02's downstream cross-day vector (F-41-03) required the structural Phase 288 supersede. F-41-03 (hero-override cross-day) was surfaced by Phase 287 JPSURF go-nuts commitment-window audit and CLOSED collaterally by Phase 288 dailyIdx structural fix (because `dailyIdx` is provably frozen across the rng-lock window, both CALL 1 and CALL 2 read the same slot regardless of physical-day boundary crossings). Phase 289 ships TST-JPSURF-01..04 cross-day regression + TST-HOFIX adjustments. All three fixes ship at v41.0 closure HEAD with pre-launch posture — zero realized capital loss; bug-class-elimination via algorithm-level structural changes.

### D-08 5-Bucket Severity Rubric

Severity calibration mapped via the v25-v40 player-reachability × value-extraction × determinism-break frame, carried forward as D-08 from v25 onward (D-41N-SEV-01 carry of D-40N-SEV-01 / D-274-SEV-01).

| Severity | Definition |
| -------- | ---------- |
| CRITICAL | Player-reachable, material protocol value extraction, no mitigation at HEAD. |
| HIGH | Player-reachable, bounded value extraction OR no extraction but hard determinism violation. |
| MEDIUM | Player-reachable, no value extraction, observable behavioral asymmetry. |
| LOW | Player-reachable theoretically but not practically (gas economics / timing / coordination cost makes exploit non-viable). |
| INFO | Not player-reachable, OR documented design decision, OR observation only. |

**F-41-01 severity at HEAD: HIGH** (per D-281-SEVERITY-01) — player-reachable + hard determinism violation + bounded value extraction (clustered-variance harm shape; no funds stolen). **F-41-02 severity at HEAD: HIGH** (with CRITICAL elevation note on `isFinalPhysicalDay_` where `dailyBps == 10_000` final-day case misallocates 100% of remaining `currentPrizePool`) — player-reachable (any bettor placing ≥ MIN_BET_ETH between CALL 1 and CALL 2) + hard determinism violation (disjoint-subset bucket invariant breaks) + bounded value extraction (~0.025-2.5 ETH per attack window on moderate pools per economic-analyst quantification). **F-41-03 severity at HEAD: MEDIUM** — catastrophy-tier likelihood (requires ≥24h `advanceGame` silence between CALL 1 and CALL 2; LOW under healthy conditions, INEVITABLE under multi-day stall) but same disjoint-subset breakage on activation; rated MEDIUM rather than HIGH because the catastrophy precondition substantially reduces realized risk envelope.

### D-09 KI Gating Rubric Reference

The Section 6 KI-eligibility 3-predicate test (D-09) is distinct from the D-08 severity rubric above. A candidate qualifies for `KNOWN-ISSUES.md` promotion iff ALL three predicates hold: (1) accepted-design (intentional / documented / load-bearing); (2) non-exploitable; (3) sticky (persists across foreseeable future revisions). All three F-41-NN findings at this milestone: **NOT KI-eligible** — each was a bug (predicate 1 false), was player-reachable + broke determinism (predicate 2 false), and is structurally eliminated at v41 close (predicate 3 false). All 3 predicates fail for all 3 findings. KNOWN-ISSUES.md is UNMODIFIED at v41 close per D-281-KI-01 — shipped-then-fixed defects are documented in §4 + §9 of the FINDINGS file, not in KNOWN-ISSUES.md. v41 sets the precedent. The "how do we record shipped-then-fixed bugs in KI" policy question is deferred until launch posture review.

### Forward-Cite Closure Summary

D-41N-FCITE-01 carry of D-40N-FCITE-01 / D-274-FCITE-01 / D-272-FCITE-01 / D-271-FCITE-01 + D-253-15 step 8 + ROADMAP terminal-phase rule: zero forward-cites emitted from Phase 284 to any post-v41.0 milestone phases. Verified at Section 8 Forward-Cite Closure block. v41.0 = 9-phase multi-phase milestone. Deferred items use locked-decision IDs + descriptive labels only (D-281-FIX-SHAPE-01 owed-salt reference pattern; D-288-FIX-SHAPE-01 dailyIdx-anchor reference pattern; D-40N-MINTBOOST-OUT-01 mint-boost retention; LBX-02 fixture-coverage gap; superseded-baseline SURF `it.skip` cleanup; indexer-side update handoff per off-chain SDK migration; hero-override mechanic activation FAQ from E3; KI policy review).

### Attestation Anchor

See Section 9 Milestone Closure Attestation for the D-253-15 step 9 attestation block triggering v41.0 milestone closure via signal `MILESTONE_V41_AT_HEAD_315978a0c18294e0d7fa5cd4cdfe7f8e5b9a95c4` (resolved at the Phase 284 terminal closure-flip commit per D-284-CLOSURE-01).

---

## 3. Per-Phase Sections

v41.0 is a 9-phase multi-phase milestone. Sections 3a-3i below give one "What IS at v41.0 close" enumeration per phase, consumed from the per-phase SUMMARY / VERIFICATION / MEASUREMENT / DESIGN-INTENT-TRACE / SWEEP-LOG / JPSURF-AUDIT artifacts — surface detail is not re-derived here. Section 3.A is the delta-surface table; Section 3.B is the zero-new-state attestation; Section 3.C is the conservation re-proof.

### 3a. Phase 281 — Mint-Batch Determinism Fix (FIX)

**Source-tree changes since baseline:**
- USER-APPROVED Wave 1 contract commit `221afcf7` — `feat(281): mint-batch determinism fix via owed-salt seed mix [FIX-01..05] (B2 symmetric)`. One file: `contracts/modules/DegenerusGameMintModule.sol` (+10 / -6 LOC; 5 logical edits at 4 sites covering both `_raritySymbolBatch` callsites). Bytecode delta +17 bytes (16304 vs 16287 baseline). Storage layout diff EMPTY. Public ABI byte-identical. Event topic hashes preserved.

**What IS at v41.0 close (Phase 281 delta):**
- **FIX-01 (W2 indexer-replay primary per D-281-FIX01-REFRAME-01)** — for any `(rk, player)` pair where `owed > writesBudget / 2` at queue-time, every `TraitsGenerated` emission carries `owed_at_call_entry` in its 4th positional field, and the keccak input tuple `(baseKey, entropy, groupIdx, owed_at_call_entry)` is unique across all such emissions for that player within a single VRF day.
- **FIX-02 (zero new storage)** — Storage layout EMPTY diff vs `cd549499`. Owed-salt reads `ticketsOwedPacked[rk][player] >> 8` already loaded on stack.
- **FIX-03 (public ABI + event topic hashes preserved)** — only the `private` helper `_raritySymbolBatch` gained a 6th positional `uint32 ownedSalt` parameter.
- **FIX-04 (TraitsGenerated.startIndex semantic shift)** — emit blocks pass `owed` as 4th positional field; ABI shape unchanged; semantic shifts from within-call cursor to `owed_at_call_entry`.
- **FIX-05 (design-intent trace lands BEFORE contract patch)** — `.planning/phases/281-*/281-01-DESIGN-INTENT-TRACE.md` covers all 4 required sections.
- **B2 symmetric scope addendum** — Phase 281 patches BOTH `_raritySymbolBatch` callsites (Path A `processFutureTicketBatch:469` + Path B `_processOneTicketEntry:803`); FIX-01 W2 audit invariant holds globally per path.

### 3b. Phase 282 — Multi-Call Drain Regression Fixture (TST-FIX)

**Source-tree changes since baseline:**
- USER-APPROVED Wave 2 test commit `a1212b00` — `test(282): multi-call drain trait-byte-identity + non-increasing 4th-field + pairwise-distinct keccak inputs + single-call byte-identity [TST-FIX-01..04] (REDUCED SCOPE per 2026-05-16 user authorization)`. Two new test surfaces (977 LOC total): `test/edge/MintBatchDeterminism.test.js` (794 LOC, 6 `it()` blocks all PASS in ~24s); `test/helpers/raritySymbolBatchRef.mjs` (183 LOC pure-JS verbatim port of `_raritySymbolBatch` body at HEAD `221afcf7`).

**What IS at v41.0 close (Phase 282 delta):**
- **TST-FIX-01..04** — W2 indexer-replay byte-identity (29 emissions Path B 2000-ticket anchor + 12 emissions Path A whale-bundle at future levels 2..5); non-increasing 4th-field; pairwise-distinct keccak inputs; single-call byte-identity. All pass.
- **B2 symmetric coverage** — both drain paths exercised per D-282-B2-COVERAGE-01.
- **Reduced-scope authorization 2026-05-16:** TST-FIX-05 hard gas ceiling DOWNGRADED to informational; TST-FIX-06 production crime-scene replay DROPPED. F-41-01 evidence class **PRODUCTION_REPLAYABLE → ALGORITHM_VERIFIED**.
- Path-accumulator pre-existing quirk documented (Path A `processed += take` vs Path B `processed += writesUsed >> 1`; PRE-EXISTING contract quirk; W2 invariant holds globally per path).

### 3c. Phase 283 — Cross-Surface Batched-Loop Sweep (SWEEP)

**Source-tree changes since baseline:** NONE. Phase 283 is DEFAULT ZERO-MUTATION wave shape — 0 USER-APPROVED contract/test commits + 1 AGENT-AUTHORED planner-private SWEEP-LOG.md artifact.

**What IS at v41.0 close (Phase 283 delta):**
- **SWEEP-01..05 (6 cooperative-yield surfaces enumerated)** — `DegenerusGameMintModule.processFutureTicketBatch` (Path A, RESOLVED via Phase 281); `_processOneTicketEntry` (Path B, RESOLVED via Phase 281 B2 symmetric); `payDailyJackpot`/`_resumeDailyEth`/`_processDailyEth` resumeEthPool 2-call ETH split (SAFE-BY-STRUCTURE preliminary + carry-forward observation routed to §4); LootboxModule auto-resolve queue + manual resolve (SAFE-BY-STRUCTURE three-no); BurnieCoinflip claim + daily resolution (SAFE-BY-STRUCTURE three-no); AdvanceModule bounty + future-ticket wrapper (SAFE-BY-STRUCTURE three-no).
- **3-Q rubric attestation per surface** — three-no → SAFE-BY-STRUCTURE; Q-ii NO via reference-pattern owed-salt → SAFE-BY-STRUCTURE.
- **`_applyHeroOverride` cross-day storage carry-forward observation (D-283-SWEEP04-01)** — hand-forwarded VERBATIM to Phase 284 §4 adversarial pass; surfaced F-41-02 at the original adversarial pass; eventually closed by Phase 288.
- Default zero-mutation wave shape achieved; TST-SWEEP-01 ZERO'd.

### 3d. Phase 285 — Hero-Override Day-Index Fix (HOFIX) — **SUPERSEDED-AT-PHASE-288**

**Source-tree changes since baseline:**
- USER-APPROVED contract commit `c4d62564` — `feat(285): hero-override day-index fix via write-side +1 offset [FIX-HOFIX-01]`. One file: `contracts/modules/DegenerusGameDegeneretteModule.sol` write-side `+1` offset on `dailyHeroWagers[_simulatedDayIndex() + 1]` at L486; plus view-fn NatSpec annotation updates at `contracts/DegenerusGame.sol`.

**What IS at v41.0 close (Phase 285 delta):** **SUPERSEDED.** Phase 288 commit `4837fa5c` REVERTS the Phase 285 write-side `+1` to canonical (`dailyHeroWagers[_simulatedDayIndex()]`) AND introduces a structural fix on the READ side (`dailyHeroWagers[dailyIdx]` via `dailyIdx` storage slot which is frozen across the rng-lock window). The net contract state at v41 close HEAD is: `dailyHeroWagers[D]` semantic = "bets placed on physical day D" (canonical) + `_applyHeroOverride` reads `dailyHeroWagers[dailyIdx]` where `dailyIdx` is the most-recent `_unlockRng` day (typically D-1 in steady state).

**Why Phase 285 was a valid intermediate fix.** Phase 285 closed F-41-02's same-day attack window structurally — `placeDegeneretteBet` writes to slot[D+1] under the Phase 285 semantic, so a bet placed on day D before today's jackpot lands in slot[D+1] (which `_applyHeroOverride` reading `_simulatedDayIndex()` does NOT consume on day D). The bet feeds day-D+1's jackpot, matching user design intent. **Why Phase 288 supersedes.** Phase 285's same-day fix did NOT close the cross-day CALL 1 / CALL 2 vector (F-41-03), because both call sites still re-evaluate `_simulatedDayIndex()` LIVE on each call; cross-day split sees `_simulatedDayIndex() = D` at CALL 1 and `_simulatedDayIndex() = D+N` at CALL 2, with `dailyHeroWagers[D+1]` populated by CALL-1-day bets and `dailyHeroWagers[D+N+1]` populated by inter-call bets — divergence possible. Phase 288 closes BOTH F-41-02 (intra-day) AND F-41-03 (cross-day) via a single structural change: read `dailyIdx` (frozen single-writer slot, `_unlockRng` is sole mutator, fires only at end-of-cycle) instead of `_simulatedDayIndex()` (live wall-clock). Phase 285 is acknowledged in the v41 timeline as the supersede pattern — fix-shape-A iteration followed by fix-shape-B structural restructure — and is documented in `audit/FINDINGS-v41.0.md` §4 F-41-02 + §3a for full audit narrative.

### 3e. Phase 286 — Hero-Override Day-Index Regression Fixture (TST-HOFIX) — **REVISED-AT-PHASE-289**

**Source-tree changes since baseline:**
- USER-APPROVED test commit `cef9a972` — `test(286): hero-override day-index regression fixture [TST-HOFIX-01..04] (TST-HOFIX-05 zeros out)`. New file: `test/edge/HeroOverrideDayIndex.test.js`.

**What IS at v41.0 close (Phase 286 delta):** **REVISED.** Phase 289 commit `ab76e990` adjusts the Phase 286 tests to the post-Phase-288 canonical semantic (slot[D] = bets placed on day D; `dailyIdx`-anchored read). The TST-HOFIX-01..04 invariants are preserved in spirit: bets placed on day D do NOT affect day-D's jackpot; bets placed on day D DO affect day-D+1's jackpot (modulo the `dailyIdx` lag — bets placed on day D feed the NEXT jackpot whose `dailyIdx == D`); 2-call ETH split read consistency under arbitrary inter-call bet interleaving; F-41-02 anchor-replay regression. Phase 289 also adds TST-JPSURF-01..04 cross-day regression coverage beyond the original TST-HOFIX scope.

### 3f. Phase 287 — Jackpot-Influence Surface Closure (JPSURF) — FLAG-ONLY

**Source-tree changes since baseline:** NONE. Phase 287 is FLAG-ONLY per user instruction 2026-05-17 — zero contract mutations; findings cataloged for follow-up user review.

**What IS at v41.0 close (Phase 287 delta):**
- **JPSURF-01 (READ-SET catalog)** — 27 storage SLOAD slots in jackpot operational call graph cataloged (`dailyHeroWagers`, `traitBurnTicket`, `deityBySymbol`, `ticketQueue` far-future, `resumeEthPool`, `dailyTicketBudgetsPacked`, `level`, `jackpotCounter`, `compressedJackpotFlag`, `currentPrizePool`, `futurePrizePool`, `levelPrizePool`, `autoRebuyState`, `gameOver`, plus 13 secondary).
- **JPSURF-02 (MUTATOR-SET)** — every external/public function across `contracts/` cataloged with `rngLockedFlag`-check verdict + mutated-slots list.
- **JPSURF-03 (cross-reference verdict table)** — per-(S, F) pair classification: SAFE_BY_DESIGN (rngLockedFlag-gated); SAFE_BY_STRUCTURE (Phase 195+ read-write buffer for ticket queues; Phase 285 era write-side `+1` for hero-wagers); VIOLATION (none at HEAD).
- **JPSURF-04 (rngLockedFlag set-at-request verdict)** — `rngLockedFlag = true` set AT `vrfCoordinator.requestRandomWords()` (not after); no frontrun gap.
- **JPSURF-05 (audit artifact)** — `.planning/phases/287-jackpot-influence-surface-closure-jpsurf/287-01-JPSURF-AUDIT.md` consolidates catalog + verdicts.
- **Result:** **0 new VIOLATIONs.** 3 residuals flagged: (i) F-41-03 candidate (cross-day CALL 1 / CALL 2 hero-override re-derivation); (ii) zero-day-hunter N-5 boundary-race amplifier; (iii) zero-day-hunter N-9 NORMAL/COMPRESSED mode partial exposure. All 3 routed to Phase 288 dailyIdx structural fix.

### 3g. Phase 288 — F-41-03 Cross-Day CALL 1/CALL 2 Determinism Fix (FIX-JPSURF)

**Source-tree changes since baseline:**
- USER-APPROVED contract commit `4837fa5c` — `feat(288): F-41-03 cross-day determinism fix via dailyIdx read; supersede Phase 285 [FIX-JPSURF-01]`. Modified files: `contracts/modules/DegenerusGameJackpotModule.sol` (`_applyHeroOverride` L1602: `_topHeroSymbol(_simulatedDayIndex())` → `_topHeroSymbol(dailyIdx)`); `contracts/modules/DegenerusGameDegeneretteModule.sol` (`_placeDegeneretteBetCore` L486: `_simulatedDayIndex() + 1` → `_simulatedDayIndex()` — reverts Phase 285 write-side `+1`); `contracts/DegenerusGame.sol` (view-fn NatSpec reverted to canonical). Bytecode delta net −36 bytes (−27 Degenerette + −9 Jackpot). Storage layout delta: 0 bytes. Public ABI byte-identical. Event topic hashes preserved.

**What IS at v41.0 close (Phase 288 delta):**
- **FIX-JPSURF-01 (structural dailyIdx anchor)** — `_applyHeroOverride` reads `dailyHeroWagers[dailyIdx]`. `dailyIdx` is a single-writer storage slot declared `uint32 internal` at `DegenerusGameStorage.sol:236`; only `_unlockRng(uint32 day)` writes it (private function, 4 callsites in `AdvanceModule` all at end-of-day-cycle gates: L330 phase-transition, L401 purchase-phase end, L466 coin+tickets end, L630 game-over drain end). The `dailyIdx` slot is **frozen across the entire rng-lock window** — between VRF request and end-of-cycle `_unlockRng`, no path mutates it. Both CALL 1 and CALL 2 of the 2-call ETH split read the IDENTICAL slot regardless of physical-day boundary crossings → disjoint-bucket-subset invariant from Phase 283 SWEEP-04 fully restored.
- **F-41-02 RESOLVED collaterally** — the within-day attack window closes because both CALL 1 and CALL 2 read `dailyHeroWagers[dailyIdx]` regardless of whether intervening bets land in `dailyHeroWagers[currentDay]` (which is NOT `dailyIdx` during the rng-lock window).
- **F-41-03 RESOLVED structurally** — the cross-day catastrophy case closes because `dailyIdx` is invariant across day boundaries during the rng-lock window (single-writer invariant).
- **Bet-write semantic restored to canonical** — `dailyHeroWagers[D]` = bets placed on day D (matches view-fn NatSpec + matches pre-Phase-285 era).

### 3h. Phase 289 — F-41-03 Cross-Day Snapshot Regression Fixture (TST-JPSURF)

**Source-tree changes since baseline:**
- USER-APPROVED test commit `ab76e990` — `test(289): adjust Phase 286 tests + F-41-03 cross-day regression [TST-JPSURF-01..04]`. Adjusts Phase 286 TST-HOFIX assertions to the post-Phase-288 canonical semantic; adds TST-JPSURF-01..04 cross-day regression coverage.

**What IS at v41.0 close (Phase 289 delta):**
- **TST-JPSURF-01** — CALL 1 and CALL 2 in same physical day produce identical `_topHeroSymbol` consumption (regression confirmation; symmetric to TST-HOFIX-03).
- **TST-JPSURF-02** — CALL 1 and CALL 2 across day-boundary produce identical `traitIds[4]` reads (dailyIdx-frozen invariant verified via storage-slot identity).
- **TST-JPSURF-03** — `dailyIdx` storage frozen across rng-lock window (slot-level identity test).
- **TST-JPSURF-04** — F-41-03 anchor-replay regression: simulates catastrophy scenario (advanceGame falls silent for ~24h after CALL 1; resume on day D+N via CALL 2); asserts disjoint-bucket-subset invariant holds via storage-slot reads.
- **9 tests PASS.** Evidence class: ALGORITHM_VERIFIED for F-41-03 (storage-slot identity test directly verifies the frozen-during-rng-lock invariant; end-to-end stage-machine execution under VRF mock + multi-cycle level progression would add empirical confidence but the structural argument is sufficient for the closure verdict).

### 3i. Phase 284 — Delta Audit + Findings Consolidation (Terminal)

**Source-tree changes since baseline:** NONE. Phase 284 is SOURCE-TREE FROZEN — `git diff cd549499..HEAD -- contracts/ test/` is fully accounted for by the 6 source-tree commits (Phase 281 + 282 + 285 + 286 + 288 + 289); Phase 284 emits zero `contracts/` and zero `test/` mutations.

**What IS at v41.0 close (Phase 284 delta):**
- `audit/FINDINGS-v41.0.md` — this 9-section terminal milestone-closure deliverable, agent-authored, FINAL READ-only (chmod 444) at v41.0 closure HEAD.
- `.planning/phases/284-*/284-01-ADVERSARIAL-LOG.md` + `284-ADVERSARIAL-CONTRACT-AUDITOR.md` + `284-ADVERSARIAL-ZERO-DAY-HUNTER.md` + `284-ADVERSARIAL-ECONOMIC-ANALYST.md` (original pass) + `284-ADVERSARIAL-RE-PASS-CONTRACT-AUDITOR.md` + `284-ADVERSARIAL-RE-PASS-ZERO-DAY-HUNTER.md` + `284-ADVERSARIAL-RE-PASS-ECONOMIC-ANALYST.md` (re-pass on Phase 288 fix).
- `KNOWN-ISSUES.md` — UNMODIFIED per D-281-KI-01.
- `.planning/ROADMAP.md` + `.planning/STATE.md` + `.planning/MILESTONES.md` + `.planning/PROJECT.md` + `.planning/REQUIREMENTS.md` — atomic closure-flip applied at the terminal closure-flip task per D-284-CLOSURE-01.

### 3.A AUDIT-01 Delta-Surface Table

Every source-tree change from v40.0 baseline `cd549499` to v41.0 HEAD `ab76e990` enumerated with hunk-level evidence and `{NEW, MODIFIED_LOGIC, REFACTOR_ONLY, DELETED, DOCS_ONLY, ANALYTICAL, SUPERSEDED}` classification per row.

**Reproduction recipe:**
```
git log --oneline cd549499..ab76e990 -- contracts/ test/
git diff --stat cd549499..ab76e990 -- contracts/ test/
git show 221afcf7   # Phase 281 contract patch (mint-batch)
git show a1212b00   # Phase 282 test fixture (mint-batch)
git show c4d62564   # Phase 285 contract patch (hero-override write-side +1; SUPERSEDED)
git show cef9a972   # Phase 286 test fixture (hero-override; REVISED)
git show 4837fa5c   # Phase 288 contract patch (dailyIdx structural fix; F-41-02 + F-41-03)
git show ab76e990   # Phase 289 test fixture (cross-day regression + TST-HOFIX adjustments)
```

Expected output: 6 source-tree commits across 2 phase-pair groups (mint-batch fix + tests = Phase 281+282; hero-override fix-iteration-then-supersede + adjusted tests = Phase 285+286+288+289).

#### Row Group 1 — Phase 281 FIX (mint-batch determinism fix via owed-salt seed mix)

| SHA | File | Hunk | Classification | Evidence |
| --- | --- | --- | --- | --- |
| `221afcf7` | `contracts/modules/DegenerusGameMintModule.sol` L544-L551 (`_raritySymbolBatch` sig) | Append `uint32 ownedSalt` 6th param + NatSpec | MODIFIED_LOGIC | New private-helper parameter |
| `221afcf7` | `contracts/modules/DegenerusGameMintModule.sol` L572 (seed keccak) | `keccak256(abi.encode(baseKey, entropyWord, groupIdx, ownedSalt))` | MODIFIED_LOGIC | 4th positional keccak input added |
| `221afcf7` | `contracts/modules/DegenerusGameMintModule.sol` L469 + L470-L477 (Path A) | Callsite passes `owed` as 6th arg + emits `owed` 4th positional | MODIFIED_LOGIC | Per D-281-STARTINDEX-SEMANTICS-01 |
| `221afcf7` | `contracts/modules/DegenerusGameMintModule.sol` L803 + L804-L811 (Path B) | B2 symmetric scope, same shape as Path A | MODIFIED_LOGIC | Per `281-01-MEASUREMENT.md §5b` |

**Row group 1 summary:** 4 hunks across 1 file; +10/-6 LOC; bytecode +17 bytes; storage layout EMPTY diff; B2 symmetric scope.

#### Row Group 2 — Phase 282 TST-FIX (mint-batch regression fixture)

| SHA | File | Hunk | Classification | Evidence |
| --- | --- | --- | --- | --- |
| `a1212b00` | `test/edge/MintBatchDeterminism.test.js` | NEW (794 LOC) | NEW | 6 `it()` blocks covering TST-FIX-01..04 across both drain paths |
| `a1212b00` | `test/helpers/raritySymbolBatchRef.mjs` | NEW (183 LOC) | NEW | Pure-JS verbatim port of `_raritySymbolBatch` body |

**Row group 2 summary:** 2 new files; 977 LOC; TST-FIX-01..04 ALGORITHM_VERIFIED for F-41-01.

#### Row Group 3 — Phase 283 SWEEP (cross-surface batched-loop; ANALYTICAL)

| SHA | File | Hunk | Classification | Evidence |
| --- | --- | --- | --- | --- |
| (no source-tree commit) | `.planning/phases/283-*/283-01-SWEEP-LOG.md` | NEW (planner-private) | ANALYTICAL | 6 per-surface 3-Q attestations + reference-pattern annotation + `_applyHeroOverride` carry-forward observation |

**Row group 3 summary:** Zero source-tree commits per default zero-mutation outcome.

#### Row Group 4 — Phase 285 HOFIX (hero-override write-side +1 fix) — **SUPERSEDED-AT-PHASE-288**

| SHA | File | Hunk | Classification | Evidence |
| --- | --- | --- | --- | --- |
| `c4d62564` | `contracts/modules/DegenerusGameDegeneretteModule.sol` L486 | `dailyHeroWagers[_simulatedDayIndex() + 1]` write key | SUPERSEDED | Reverted by Phase 288 `4837fa5c` |
| `c4d62564` | `contracts/DegenerusGame.sol` view-fn NatSpec | Phase-285-era jackpot-day annotation | SUPERSEDED | Reverted by Phase 288 to canonical |

**Row group 4 summary:** Phase 285 net contribution to v41 close HEAD = ZERO (Phase 288 reverts the write-side `+1` AND restores view-fn NatSpec). Phase 285 is documented in the timeline as a valid intermediate fix that closed F-41-02's intra-day window; structurally superseded by Phase 288 which closes BOTH F-41-02 + F-41-03 via the read-side `dailyIdx` anchor.

#### Row Group 5 — Phase 286 TST-HOFIX (hero-override regression) — **REVISED-AT-PHASE-289**

| SHA | File | Hunk | Classification | Evidence |
| --- | --- | --- | --- | --- |
| `cef9a972` | `test/edge/HeroOverrideDayIndex.test.js` | NEW | NEW (REVISED) | Adjusted by Phase 289 `ab76e990` to post-Phase-288 canonical semantic |

**Row group 5 summary:** Phase 286 tests authored against Phase 285 semantic; Phase 289 adjusts assertions to post-Phase-288 canonical.

#### Row Group 6 — Phase 287 JPSURF (commitment-window audit; ANALYTICAL, FLAG-ONLY)

| SHA | File | Hunk | Classification | Evidence |
| --- | --- | --- | --- | --- |
| (no source-tree commit) | `.planning/phases/287-*/287-01-JPSURF-AUDIT.md` | NEW (planner-private) | ANALYTICAL | 27-slot READ-SET catalog + MUTATOR-SET catalog + per-(S,F) verdict table + 0 VIOLATIONs + F-41-03 candidate flagged |

**Row group 6 summary:** Zero source-tree commits per FLAG-ONLY user posture.

#### Row Group 7 — Phase 288 FIX-JPSURF (dailyIdx structural fix; supersedes Phase 285)

| SHA | File | Hunk | Classification | Evidence |
| --- | --- | --- | --- | --- |
| `4837fa5c` | `contracts/modules/DegenerusGameJackpotModule.sol` L1602 (`_applyHeroOverride`) | `_topHeroSymbol(_simulatedDayIndex())` → `_topHeroSymbol(dailyIdx)` | MODIFIED_LOGIC | Operational read swap to frozen single-writer slot |
| `4837fa5c` | `contracts/modules/DegenerusGameDegeneretteModule.sol` L486 (`_placeDegeneretteBetCore`) | `_simulatedDayIndex() + 1` → `_simulatedDayIndex()` | MODIFIED_LOGIC (REVERTS PHASE 285) | Bet-write key reverts to canonical |
| `4837fa5c` | `contracts/DegenerusGame.sol` view-fn NatSpec | Phase-285-era annotation reverted to canonical | DOCS_ONLY (REVERTS PHASE 285) | NatSpec restored to "slot[D] = bets placed on day D" |

**Row group 7 summary:** Bytecode net −36 bytes (−27 Degenerette + −9 Jackpot). Storage layout 0-byte diff. ABI byte-identical. F-41-02 + F-41-03 RESOLVED.

#### Row Group 8 — Phase 289 TST-JPSURF (cross-day regression + TST-HOFIX adjustments)

| SHA | File | Hunk | Classification | Evidence |
| --- | --- | --- | --- | --- |
| `ab76e990` | `test/edge/HeroOverrideDayIndex.test.js` | Adjusted TST-HOFIX-01..04 to post-Phase-288 canonical | MODIFIED_LOGIC (REVISES PHASE 286) | Slot[D] = bets placed on day D semantic |
| `ab76e990` | `test/edge/HeroOverrideCrossDay.test.js` (or equivalent) | NEW TST-JPSURF-01..04 cross-day regression | NEW | Storage-slot dailyIdx frozen invariant + cross-day fixture |

**Row group 8 summary:** 9 tests PASS. F-41-03 ALGORITHM_VERIFIED via storage-slot identity.

#### Row Group 9 — Phase 284 TERMINAL (audit deliverable; SOURCE-TREE FROZEN)

| SHA | File | Hunk | Classification | Evidence |
| --- | --- | --- | --- | --- |
| (closure commit) | `audit/FINDINGS-v41.0.md` | NEW (this deliverable) | NEW | 9-section terminal audit; chmod 444 |
| (closure commit) | `.planning/ROADMAP.md` + `STATE.md` + `MILESTONES.md` + `PROJECT.md` + `REQUIREMENTS.md` | Closure-flip atomic | DOCS_ONLY | Per D-284-CLOSURE-01 |

**Row group 9 summary:** Zero `contracts/` + zero `test/` mutations per terminal-phase invariant.

#### Section 3.A Summary

6 USER-APPROVED source-tree commits + 2 ANALYTICAL planner-private artifacts (Phase 283 SWEEP-LOG + Phase 287 JPSURF-AUDIT). Total source-tree footprint: 3 modified `contracts/` files (`DegenerusGameMintModule.sol` Phase 281; `DegenerusGameJackpotModule.sol` + `DegenerusGameDegeneretteModule.sol` Phase 288); 3 new/modified `test/` files. Zero `KNOWN-ISSUES.md` mutations. Phase 285 contract bytes reverted at v41 close HEAD by Phase 288 (Phase 285 listed as SUPERSEDED in the timeline; net contribution to v41 close = ZERO bytes).

### 3.B AUDIT-04 Zero-New-State Attestation

Five-row roll-up per the v36..v40 audit-attestation pattern. Phase 281 fix-shape is **(c) owed-salt** per D-281-FIX-SHAPE-01 — zero new storage + zero new SLOAD + zero new SSTORE. Phase 288 fix-shape is **(R3 equivalent) dailyIdx anchor** — zero new storage (`dailyIdx` is a pre-existing slot from v40 baseline); zero new SLOAD beyond the substitution (one fewer internal call to `_simulatedDayIndex()` per `_applyHeroOverride` invocation; one new SLOAD on `dailyIdx`); zero new SSTORE.

| Attestation row | Verdict | Evidence |
| --- | --- | --- |
| **New storage slots** | ZERO | Phase 281 storage layout EMPTY diff per `281-01-MEASUREMENT.md §2`. Phase 288 storage layout 0-byte diff per `288-01-COMMIT-MESSAGE.md` (no `DegenerusGameStorage.sol` change in commit `4837fa5c --stat`). |
| **New public/external mutation entry points** | ZERO | Phase 281: only private helper `_raritySymbolBatch` gained 6th positional param. Phase 288: only `_applyHeroOverride` internal-fn body modified (one SLOAD swap) + `_placeDegeneretteBetCore` internal-fn body modified (one expression simplification, reverting Phase 285's `+1`). All public selectors preserved per `git diff --stat` ABI parity. |
| **New admin entry points** | ZERO | Neither Phase 281 nor Phase 288 adds new admin functions. |
| **New modifiers** | ZERO | Neither phase adds Solidity modifiers. |
| **New upgrade hooks** | ZERO | Neither phase adds initializers / storage gaps / proxy admin entries / `_authorizeUpgrade` mutations. |

**Gas overhead attestation (per `feedback_gas_worst_case.md` theoretical FIRST discipline):**
- **Phase 281:** theoretical worst-case ≤2880 cumulative gas across 5840-trait drain (≤30 gas per `_raritySymbolBatch` invocation × 20 outer-loop iterations × ≤6 gas keccak-word-cost) per `281-01-MEASUREMENT.md §3a`. Phase 282 empirical patched-side gas (216,449,415 total / 8,354,736 max / 6,764,044 avg across 32 advanceGame txs) reported informationally (D-282-GAS-EMPIRICAL-01 DOWNGRADED).
- **Phase 288:** bytecode delta net −36 bytes (Jackpot −9, Degenerette −27); per-invocation gas delta: one fewer internal CALL to `_simulatedDayIndex()` + one extra SLOAD on `dailyIdx` — net approximately zero per `_applyHeroOverride` invocation; on the bet-write side, removal of `uint32 + 1` ADD opcode + overflow check saves ~30 gas per `placeDegeneretteBet`. Per `288-01-COMMIT-MESSAGE.md`.

### 3.C AUDIT-03 Conservation Re-Proof

Four-part conservation re-proof per AUDIT-03 (augmented from 3-part v40 shape to include the hero-override dailyIdx invariant):

**(i) Total-traits-credited invariant:** Sum over all `(rk, player)` of `_raritySymbolBatch.count` = sum of all queued ticket awards (`owed` consumed across all calls). Pre-Phase-281 fix: invariant held. Post-Phase-281: invariant preserved by construction — owed-salt modifies only the seed input, NOT the `count` argument. Phase 282 TST-FIX-01 empirically witnesses (8000 traits credited across 2000-ticket anchor drain match-by-match). Phase 288 does not touch this invariant (orthogonal surface).

**(ii) Bit-slice independence:** Phase 281 owed-salt is INTERNAL to MintModule per-group keccak chain — no preimage collision with bits[0..12] jackpot path-select / bits[152..167] lootbox Bernoulli / bits[200..215] jackpot Bernoulli. Phase 288 does not introduce any new entropy slice — `dailyIdx` is a day-index integer fed into a mapping lookup, NOT an entropy consumer; the value is structurally distinct from any RNG input. Both fixes preserve bit-slice independence.

**(iii) Storage byte-identity for non-mutated slots:** `forge inspect storageLayout` diff for both `DegenerusGameMintModule` and `DegenerusGameStorage` exit 0 vs `cd549499` baseline post-Phase-281. `DegenerusGameStorage.sol` 0-byte change post-Phase-288 (verified via `git show 4837fa5c --stat`). `DegenerusGame.sol` storage layout 0-byte diff (only NatSpec changed). All non-mutated slots across all storage contracts remain byte-identical between v40 close HEAD and v41 close HEAD.

**(iv) Hero-override `dailyIdx` read-consistency invariant (F-41-02 + F-41-03 closure):** `_applyHeroOverride` reads `dailyHeroWagers[dailyIdx]` at every invocation. `dailyIdx` is the sole-writer of `_unlockRng(uint32 day)` (private function in `AdvanceModule`; 4 callsites all at end-of-day-cycle gates). **Proof of frozen-during-rng-lock-window:**

Window definition: `[vrfCoordinator.requestRandomWords() at AdvanceModule:1100 → _unlockRng() at AdvanceModule:1697]`. Within this window, the following hold:
- (a) `dailyIdx` is NOT written by VRF callback (`rawFulfillRandomWords` at `AdvanceModule:1717` writes `rngWordCurrent`, NOT `dailyIdx`).
- (b) `dailyIdx` is NOT written by any external/public function (grep across `contracts/` confirms only `_unlockRng` writes it).
- (c) `dailyIdx` is NOT written by admin escape `updateVrfCoordinatorAndSub` (verified via full function read; admin clears `rngLockedFlag`, `vrfRequestId`, `rngRequestTime`, `rngWordCurrent`, but NOT `dailyIdx`).
- (d) `_unlockRng` callsites are mutually exclusive with the rng-lock window: L330 (post-phase-transition FF drain end), L401 (post-purchase-phase-daily end), L466 (post-coin+tickets end), L630 (post-game-over-drain end). All four are AT THE END of the rng-lock window (the window itself terminates as `_unlockRng` fires).

Consequence: both CALL 1 (within rng-lock window day D) and CALL 2 (within same rng-lock window day D+N) read the IDENTICAL `dailyHeroWagers[dailyIdx]` slot. The hero-override application is deterministic across the split → `traitIds[heroQuadrant]` is identical → `_pickSoloQuadrant(traitIds, entropy)` produces identical `soloQuadrant` → `effectiveEntropy` is identical → `bucketCounts` is identical → `order` is identical → `call1Bucket` mask is identical → **disjoint-bucket-subset structural invariant from Phase 283 SWEEP-04 Trace #5 is fully restored** under both intra-day and cross-day cases. F-41-02 and F-41-03 are RESOLVED via this single structural change.

---

## 4. F-41-NN Finding Blocks + Adversarial Sweep

### 4.0 F-41-01 — Mint-Batch Cross-Call Determinism Defect (RESOLVED_AT_V41)

**Severity:** HIGH (per D-08 + D-281-SEVERITY-01).
**Status:** RESOLVED_AT_V41.
**Evidence class:** `ALGORITHM_VERIFIED` (per Phase 282 reduced-scope authorization 2026-05-16).
**Citation chain:** `D-281-FIX-SHAPE-01` + Phase 281 commit `221afcf7` + Phase 282 commit `a1212b00`.

**Description.** At v40.0 closure HEAD `cd549499`, `_raritySymbolBatch` at MintModule:567-569 keccak-seeded on `(baseKey, entropyWord, groupIdx)`. The stack-local `uint32 processed` at L419/L695 was load-bearing for cross-call seed distinctness: when `owed > writesBudget = 550`, the outer-loop yielded mid-player; the next call re-entered with `processed = 0`, regenerating identical `keccak256(baseKey, entropyWord, 0)` seeds and emitting identical 292-trait sequences. Realized on-chain at blocks 10862393..10862412 (20 byte-identical `TraitsGenerated(player, lvl=1, queueIdx=6, startIndex=0, count=292, entropy=2f02…)` events).

**Fix.** Phase 281 commit `221afcf7` adds owed-salt 4th keccak input: `keccak256(abi.encode(baseKey, entropyWord, groupIdx, ownedSalt))` where `ownedSalt = uint32(ticketsOwedPacked[rk][player] >> 8)` read AT OUTER-LOOP ITERATION ENTRY (MintModule:427 Path A; :770 Path B). `ownedSalt` is monotonically decreasing across the multi-call drain (each call deducts `take` from owed before the next call's storage re-read), so the 4th keccak input is provably distinct between any two calls processing the same player at the same `idx`. Zero new SLOAD/SSTORE/storage slot; zero MEV surface; B2 symmetric scope covers both drain paths.

**Post-fix invariant (W2 indexer-replay primary per D-281-FIX01-REFRAME-01).** For any `(rk, player)` pair where `owed > writesBudget / 2` at queue-time, every `TraitsGenerated` emission for that player within a single VRF day carries `owed_at_call_entry` in its 4th positional field. The keccak input tuple `(baseKey, entropy, groupIdx, owed_at_call_entry)` is unique across all such emissions. An off-chain indexer can reconstruct the exact trait multiset from the emission set alone.

**Backward-trace + commitment-window attestation.** Owed-salt is on-chain deterministic from accumulated drain state (per-iteration distinctness structurally guaranteed because `owed` strictly decreases on writeback) but unknown at the player's input-commitment time. Player cannot influence `owed_at_call_entry` at resumption time (writebacks at MintModule:496 are unconditional). Commitment-window check is degenerate PASS.

**Regression coverage.** Phase 282 commit `a1212b00` ships 4 `it()` blocks covering TST-FIX-01..04 across the B2 symmetric scope (Path B 2000-ticket drain — 29 emissions; Path A whale-bundle at future levels — 12 emissions). All PASS in ~24s.

**Harm characterization.** Duplicate trait sets are themselves valid random draws from the trait distribution — bug made 20 successive draws produce the SAME draw instead of 20 independent draws. Realized harm shape: clustered variance on the affected whale (over-representation in those trait IDs, under-representation in others); NOT distribution-bias against the broader player base; no funds impact; no fairness impact on other players; bounded rewindable pre-launch.

**Adversarial-pass disposition.** Original pass (post-Phase-282 §4 draft): 3-skill PARALLEL consensus 9 of 10 hypotheses SAFE-variant; Hypothesis (ix) `_applyHeroOverride` cross-day vector ELEVATED → F-41-02. Re-pass on Phase 288 dailyIdx fix: 3-skill consensus 0 FINDING_CANDIDATEs; F-41-01 ALGORITHM_VERIFIED status preserved.

---

### 4.0a F-41-02 — Hero-Override Day-Index (Within-Day) (RESOLVED_AT_V41)

**Severity:** HIGH (with CRITICAL elevation note on `isFinalPhysicalDay_` where `dailyBps == 10_000` — final-day exposure misallocates 100% of remaining `currentPrizePool`).
**Status:** RESOLVED_AT_V41.
**Evidence class:** `ALGORITHM_VERIFIED` per D-285-EVIDENCE-CLASS-01 carry.
**Citation chain:** `D-285-FIX-SHAPE-01` (Phase 285, SUPERSEDED) + `D-288-FIX-SHAPE-01` (Phase 288, final) + Phase 285 commit `c4d62564` (SUPERSEDED) + Phase 288 commit `4837fa5c` (final) + Phase 286 commit `cef9a972` (REVISED) + Phase 289 commit `ab76e990` (final).

**Description (the bug at v40 baseline).** At v40.0 closure HEAD `cd549499`, `_applyHeroOverride` (called from `_rollWinningTraits` at `JackpotModule:455-456` and `:1180`) read `dailyHeroWagers[_simulatedDayIndex()][q]` LIVE on every invocation at `JackpotModule:1595`. In the daily-jackpot 2-call ETH split, CALL 1 fired on physical day D and CALL 2 on D+N (N ≥ 0; N ≥ 1 in the cross-day case which is the dominant production pattern because `_unlockRng` does not fire between calls and the L237 `NotTimeYet` gate forces CALL 2 onto a later physical day). Within-day attack vector: an attacker placed `placeDegeneretteBet` between CALL 1 and CALL 2 mutating `dailyHeroWagers[D][q]`; CALL 2's `_topHeroSymbol(D)` returned an attacker-biased `(heroQuadrant, heroSymbol)`; divergent `_applyHeroOverride` mutation on `traits[heroQuadrant]` cascaded through `_pickSoloQuadrant → effectiveEntropy → bucketCounts → order → call1Bucket` mask; disjoint-bucket-subset invariant from Phase 283 SWEEP-04 broke (bucket double-paid or skipped).

**Fix evolution.** Phase 285 commit `c4d62564` applied write-side `+1` offset: `dailyHeroWagers[_simulatedDayIndex() + 1][q]` at bet-write site (`DegeneretteModule:486`). This closed the intra-day attack window because day-D bets land in slot[D+1], and day-D's jackpot reads slot[D] (which holds day-D-1 bets — unaffected by intra-day attacker activity). Phase 285 was a valid intermediate fix for F-41-02's same-day vector. Phase 288 commit `4837fa5c` applies the structural fix: `_applyHeroOverride` reads `dailyHeroWagers[dailyIdx][q]` via `_topHeroSymbol(dailyIdx)` at `JackpotModule:1602`. `dailyIdx` is a single-writer storage slot (`_unlockRng` is the sole writer; private function with 4 end-of-cycle callsites); it is FROZEN across the entire rng-lock window. Phase 288 simultaneously REVERTS Phase 285's write-side `+1` to canonical (`dailyHeroWagers[_simulatedDayIndex()]` at bet-write site), restoring `slot[D] = bets placed on day D` semantic. Net contract state at v41 close = Phase 288 canonical (Phase 285 net bytecode contribution = zero). Phase 288 closes both F-41-02 (intra-day) AND F-41-03 (cross-day) via a single structural change.

**Post-fix invariant (W2 wording).** For any rng-lock window (between `requestRandomWords` and `_unlockRng`), `dailyIdx` is invariant. Both CALL 1 and CALL 2 of the 2-call ETH split read `dailyHeroWagers[dailyIdx][q]` returning IDENTICAL values regardless of physical-day boundary crossings or intervening `placeDegeneretteBet` calls (intervening bets land in `dailyHeroWagers[currentDay][q]` which is NOT `dailyIdx` during the window). `_applyHeroOverride` produces identical `traits[heroQuadrant]` mutations across both calls. Disjoint-bucket-subset invariant from Phase 283 SWEEP-04 Trace #5 is fully restored.

**Backward-trace attestation.** `dailyIdx` traces backward to its sole writer `_unlockRng(uint32 day)` at `AdvanceModule:1696-1703`. Private function. 4 callsites enumerated via `grep -rn "_unlockRng" contracts/`: L330 (phase-transition close), L401 (purchase-phase-daily end), L466 (coin+tickets end), L630 (game-over drain end). All four are AT THE END of an advanceGame stage path that consumes the rng word; subsequent `advanceGame` invocations restart the rng-lock cycle. NO admin path, NO error-recovery path, NO callback path writes `dailyIdx`. Single-writer rule provides the strongest possible invariant for frozen-during-window.

**Commitment-window attestation.** `dailyHeroWagers[dailyIdx]` is the canonical commitment-window subject for hero-override. At `requestRandomWords` (window start), `dailyIdx` is already set to the previous-day-unlock value; CALL 1 fires after VRF fulfillment within the same window; CALL 2 fires within the same window (or a subsequent rng-lock window that has not yet been entered — the cross-day case is handled because `dailyIdx` is still pre-CALL-1 value, set by the LAST `_unlockRng` before this window started). The bet-write site `placeDegeneretteBet` writes to `dailyHeroWagers[currentDay]` (wall-clock-derived), but `currentDay` ≠ `dailyIdx` during the rng-lock window. Player-controllable state in the commitment-window check: PASS — no path mutates the slot the jackpot reads.

**Regression coverage.** Phase 286 TST-HOFIX-01..04 (REVISED by Phase 289 to post-Phase-288 canonical semantic): bets on day D do NOT affect day-D's jackpot; bets on day D DO affect the NEXT jackpot whose `dailyIdx == D`; 2-call ETH split read consistency under arbitrary inter-call bet interleaving; F-41-02 anchor-replay regression. Phase 289 TST-JPSURF-03 directly verifies the dailyIdx storage-frozen-during-rng-lock invariant at the storage-slot level. 9 tests PASS.

**Severity reconciliation.** HIGH baseline per 3-skill consensus (original adversarial pass on Phase 283 hand-forward). CRITICAL elevation note on `isFinalPhysicalDay_` where `dailyBps == 10_000` (per `_dailyCurrentPoolBps`): on the final physical day, the divergence would misallocate 100% of `currentPrizePool` (rather than the typical 6-14% daily share). Single-day-amplification case. Post-Phase-288 fix: HIGH severity neutralized to RESOLVED_AT_V41; CRITICAL elevation case neutralized identically because the dailyIdx frozen invariant applies on final-day as on any other day.

**Adversarial-pass disposition.** Original pass: 3-of-3 FINDING_CANDIDATE → ELEVATED_TO_FINDING. Re-pass on Phase 288 fix: 3-skill consensus SAFE / SAFE_BY_STRUCTURAL_CLOSURE / NEGATIVE_RESULT_ONLY across all 7 hypotheses A..G (contract-auditor) + 14 hypotheses N1..N14 (zero-day-hunter) + 7 hypotheses E1..E7 + 3 beyond-scope B-04..B-06 (economic-analyst). Zero FINDING_CANDIDATE residual from Phase 288.

---

### 4.0b F-41-03 — Hero-Override Day-Index (Cross-Day Catastrophy) (RESOLVED_AT_V41)

**Severity:** MEDIUM (catastrophy-tier — precondition requires ≥24h `advanceGame` silence between CALL 1 and CALL 2; LOW under healthy conditions, INEVITABLE under multi-day stall).
**Status:** RESOLVED_AT_V41.
**Evidence class:** `ALGORITHM_VERIFIED`.
**Citation chain:** Phase 287 JPSURF audit (surfaced) + `D-285-FIX-SHAPE-01` (Phase 285 initial attempt — did NOT close cross-day case) + `D-288-FIX-SHAPE-01` (Phase 288 structural fix — closes BOTH F-41-02 AND F-41-03 collaterally) + Phase 288 commit `4837fa5c` + Phase 289 commit `ab76e990` (TST-JPSURF-04 anchor-replay regression).

**Description (the bug at v40 baseline + Phase 285 era).** Even after Phase 285's write-side `+1` closed F-41-02's intra-day window, the cross-day CALL 1 / CALL 2 vector remained open because both call sites still re-evaluated `_simulatedDayIndex()` LIVE. In the catastrophy scenario where `advanceGame` falls silent for ≥24h between CALL 1 (day D) and CALL 2 (day D+N, N ≥ 1), CALL 1 evaluated `_simulatedDayIndex() = D` and read `dailyHeroWagers[D]` (Phase 285 era) or `dailyHeroWagers[D-1]` (canonical era); CALL 2 evaluated `_simulatedDayIndex() = D+N` and read `dailyHeroWagers[D+N]` (Phase 285 era) or `dailyHeroWagers[D+N-1]` (canonical era). Both slots could contain different population distributions, especially if intervening days had organic degenerette bet activity. Divergent reads → divergent `traits[heroQuadrant]` → cascade as F-41-02 → disjoint-bucket-subset invariant breaks. Surfaced by Phase 287 JPSURF audit + zero-day-hunter N-5 (boundary-race amplifier) + N-9 (NORMAL/COMPRESSED mode partial exposure).

**Fix.** Phase 288 commit `4837fa5c` closes F-41-03 collaterally via the same structural change that closes F-41-02: `_applyHeroOverride` reads `dailyHeroWagers[dailyIdx]` instead of `dailyHeroWagers[_simulatedDayIndex()]`. Because `dailyIdx` is provably frozen across the entire rng-lock window (single-writer rule; sole writer `_unlockRng` fires only at end-of-cycle), both CALL 1 and CALL 2 read the IDENTICAL slot regardless of how many physical days have elapsed between them. The `_simulatedDayIndex()`-re-evaluation vector is structurally eliminated.

**Mode neutralization verdict.** Per zero-day-hunter re-pass N-5 + N-7 + N-9: **NORMAL mode** (each logical day = one physical day; every split crosses day boundary) is FULLY CLOSED post-Phase-288. **COMPRESSED mode** (5 logical days → 3 physical days; some logical-day pairs span 2 physical days) is FULLY CLOSED post-Phase-288. **TURBO mode** (5 logical days collapse to 1 physical day; CALL 1 and CALL 2 happen in the SAME physical day) was already neutralized pre-fix (same-day means same `_simulatedDayIndex()`); post-Phase-288 the closure mechanism is unified across all 3 modes (dailyIdx-anchored read is mode-independent).

**Backward-trace + commitment-window attestation.** Same as F-41-02 §4.0a — both depend on the dailyIdx frozen-during-rng-lock invariant. The cross-day case is structurally identical to the intra-day case under the dailyIdx anchor; the bug was that `_simulatedDayIndex()` is wall-clock-derived and therefore NOT frozen, while `dailyIdx` is stage-machine-driven and IS frozen.

**Regression coverage.** Phase 289 TST-JPSURF-01 (same-day consistency), TST-JPSURF-02 (cross-day consistency via storage-slot identity), TST-JPSURF-03 (dailyIdx frozen invariant at storage-slot level), TST-JPSURF-04 (catastrophy anchor-replay: simulates ~24h silence between CALL 1 and CALL 2 via storage reads + view function calls; asserts disjoint-bucket-subset invariant holds). End-to-end stage-machine execution under VRF mock would add empirical confidence but the structural argument is sufficient for the closure verdict (the dailyIdx single-writer rule is inspectable directly via grep + view).

**Severity rationale.** Rated MEDIUM rather than HIGH because the catastrophy precondition (≥24h `advanceGame` silence between CALL 1 and CALL 2) substantially reduces realized risk envelope under healthy operating conditions. Per economic-analyst re-pass E2-b: the gap-day handler covers coinflip payouts during stalls; there is no analogous backfill for `dailyHeroWagers`; under multi-day stall, the divergence could land in any single bucket per cycle. Pre-launch posture: zero realized capital loss. Post-Phase-288: vector structurally eliminated.

**Adversarial-pass disposition.** Surfaced by Phase 287 JPSURF audit (not original Phase 284 first-pass; the original pass surfaced F-41-02 which already covered the within-day case). Re-pass on Phase 288 fix: 3-skill consensus SAFE / SAFE_BY_STRUCTURAL_CLOSURE / NEGATIVE_RESULT_ONLY; zero residual FINDING_CANDIDATE.

---

### 4.1 11-Surface Carry-Forward Enumeration — v40 Surfaces RE_VERIFIED at v41 close

The 11 v40 adversarial surfaces (a)..(k) from `audit/FINDINGS-v40.0.md` §4.1 are RE_VERIFIED at v41 close. The v41 audit subject (Phase 281 + Phase 288 contract patches) touches `DegenerusGameMintModule.sol`, `DegenerusGameJackpotModule.sol` `_applyHeroOverride` body, `DegenerusGameDegeneretteModule.sol` `_placeDegeneretteBetCore` body, and `DegenerusGame.sol` view-fn NatSpec only. The v40-scoped surfaces (Bernoulli paths, event topic hashes, sentinel retirement, wrapper retirement, mint-boost, whole-BURNIE floors) are NOT touched outside the NatSpec/operational-read changes documented above.

| Surface | v40 verdict | v41 RE_VERIFIED? | Notes |
| --- | --- | --- | --- |
| (a) EV-neutrality of Bernoulli collapse on auto-resolve | SAFE_BY_DESIGN | YES | LootboxModule body untouched |
| (b) EV-neutrality of Bernoulli on jackpot ticket-roll | SAFE_BY_DESIGN | YES | `_jackpotTicketRoll` body untouched |
| (c) Bit-slice [152..167] reuse on auto-resolve | SAFE_BY_DESIGN | YES | LootboxModule untouched |
| (d) Bit-slice [200..215] independence on jackpot | SAFE | YES | JackpotModule entropy chain untouched (only `_applyHeroOverride` operational read modified) |
| (e) Silent cold-bust gating predicate | SAFE_BY_DESIGN | YES | LootboxModule + JackpotModule cold-bust path untouched |
| (f) Event topic-hash change correctness | SAFE | YES | Event declarations preserved across Phase 281/288 |
| (g) Index-sentinel retirement byte-equivalence | SAFE | YES | `index != type(uint48).max` retired at v40, no resurrection |
| (h) `_queueLootboxTickets` wrapper retirement + ENT-05 keccak refactor | SAFE_BY_STRUCTURAL_CLOSURE | YES | EXC-04 preserved STRUCTURALLY ELIMINATED |
| (i) Mint-boost path byte-equivalent | SAFE_BY_STRUCTURAL_CLOSURE | YES | `_queueTicketsScaled` + `_rollRemainder` + `rem` byte preserved per D-40N-MINTBOOST-OUT-01 |
| (j) Lootbox spin BURNIE floor at LootboxModule:1080 | SAFE_BY_DESIGN | YES | Floor present at v41 HEAD |
| (k) JackpotModule near/far-future coin jackpot BURNIE floor | SAFE_BY_DESIGN | YES | Floors at :1842/:1922 preserved |

**Section 4.1 verdict:** All 11 v40 surfaces RE_VERIFIED at v41 close.

---

### 4.2 v41 Adversarial Surfaces — Original 3-Skill PARALLEL Adversarial Pass (post-Phase-282 § draft)

10 hypothesis surfaces (i)..(x) charged at the original 3-skill PARALLEL adversarial pass per D-284-ADVERSARIAL-CHARGE-01. Full charge body at `.planning/phases/284-*/284-ADVERSARIAL-CHARGE.md`; per-skill reports at `284-ADVERSARIAL-CONTRACT-AUDITOR.md` + `284-ADVERSARIAL-ZERO-DAY-HUNTER.md` + `284-ADVERSARIAL-ECONOMIC-ANALYST.md`.

**Per-hypothesis consensus disposition (orchestrator-aggregated):**

| # | Hypothesis | Disposition |
| - | --- | --- |
| (i) | Owed-salt re-introduces a different determinism break | 3-skill SAFE / SAFE_BY_STRUCTURAL_CLOSURE |
| (ii) | Bit-collision against existing entropy consumers | 3-skill SAFE_BY_DESIGN / NEGATIVE_RESULT_ONLY |
| (iii) | LCG semantic shift inside `_raritySymbolBatch` | 3-skill SAFE — LCG statistical properties preserved |
| (iv) | `ticketsOwedPacked` reader updates needed outside patched paths | 3-skill SAFE — full grep enumeration |
| (v) | 3rd `payDailyJackpot` invocation in same rng cycle | 3-skill SAFE_BY_STRUCTURAL_CLOSURE — stage-machine gates |
| (vi) | Caller-path bypass of stage-machine gate | 3-skill SAFE_BY_STRUCTURAL_CLOSURE — only `advanceGame` reaches |
| (vii) | Bucket-subset manipulation via trait-count or MEV ordering | 3-skill SAFE (vector routes through (ix)) |
| (viii) | `bucketShares` parity across CALL 1 vs CALL 2 due to ethPool inputs | 3-skill SAFE — uint128 cast non-lossy in practice |
| **(ix)** | **`_applyHeroOverride` cross-day storage read divergence** | **3-of-3 FINDING_CANDIDATE → ELEVATED_TO_FINDING F-41-02 (HIGH; closes via Phase 285 → SUPERSEDED by Phase 288)** |
| (x) | Current-level path (Path B) inherits same hypothesis surface as Path A | 3-skill SAFE — Path B inherits (i)..(iv) safe dispositions |

**Severity revision.** F-41-01 severity HIGH unchanged. F-41-02 (new) HIGH with CRITICAL elevation note for `isFinalPhysicalDay_`.

---

### 4.3 v41 Adversarial Surfaces — RE-PASS on Phase 288 dailyIdx Fix

3-skill PARALLEL RE-PASS per D-284-ADVERSARIAL-RE-PASS-01 on Phase 288 commit `4837fa5c` + Phase 289 commit `ab76e990`. Charge: hunt residual vectors after the Phase 288 dailyIdx structural fix. Per-skill reports at `284-ADVERSARIAL-RE-PASS-CONTRACT-AUDITOR.md` + `284-ADVERSARIAL-RE-PASS-ZERO-DAY-HUNTER.md` + `284-ADVERSARIAL-RE-PASS-ECONOMIC-ANALYST.md`.

**Contract-auditor disposition (Hypotheses A..G):**

| # | Hypothesis | Disposition |
| - | --- | --- |
| (A) | `dailyIdx` manipulation by attacker | SAFE_BY_STRUCTURAL_CLOSURE (single-writer rule; sole writer `_unlockRng`) |
| (B) | Phase 285 supersede leaves state inconsistency | SAFE_BY_DESIGN (pre-launch posture; no production state under Phase 285 semantic) |
| (C) | `dailyIdx` vs `_simulatedDayIndex()` mismatch creates indexer edge cases | SAFE_BY_DESIGN (event metadata wall-clock convention; mapping convention indexer-resolvable) |
| (D) | Bytecode shrinkage hiding logic loss | SAFE (−36 bytes net fully accounted for) |
| (E) | Cross-day boundary edge cases beyond F-41-03 | SAFE_BY_STRUCTURAL_CLOSURE + ACCEPTED_DESIGN (governance hatch unrelated to Phase 288 scope) |
| (F) | `getDailyHeroWager` view function semantic | ACCEPTED_DESIGN (off-chain indexer migration note — recommended for deliverable) |
| (G) | Novel-vector re-walk | NEGATIVE_RESULT_ONLY (no new vectors identified) |

**Zero-day-hunter disposition (Hypotheses N1..N14):**

| # | Hypothesis | Disposition |
| - | --- | --- |
| (N1) | Multi-day stall + `_handleGameOverPath` reads stale dailyIdx | SAFE (stranded-bet UX residual under N1.b; not a finding) |
| (N2) | `_backfillGapDays` mutating dailyIdx mid-window | SAFE (verified by full function read; no dailyIdx touch) |
| (N3) | Admin `updateVrfCoordinatorAndSub` interaction with dailyIdx | SAFE (stale-window observation documented; no security surface) |
| (N4) | Unexpected `_unlockRng` callsites | SAFE (4 callsites enumerated; all end-of-cycle) |
| (N5) | TURBO mode + dailyIdx semantics | SAFE (TURBO collapses 5 logical days into 1 physical day; same frozen slot) |
| (N6) | Indexer replay divergence post-supersede | NEGATIVE_RESULT_ONLY (no on-chain semantic mismatch) |
| (N7) | Phase 287 N-* CLOSED items re-verification | SAFE (N-1..N-10 all re-verified; N-5 + N-9 NOW FULLY CLOSED) |
| (N8) | Composition with Phase 280 v40 closed surfaces (a..k) | SAFE (Surface (d) trait-holder selection STRENGTHENED by Phase 288) |
| (N9) | `DailyWinningTraits` event-vs-storage indexer skew during stall | NEGATIVE_RESULT_ONLY (UX/SDK concern, not contract finding) |
| (N10) | Function-selector / storage-layout regression check | SAFE (0-byte storage delta; ABI parity) |
| (N11) | Purchase-phase hero-override consistency | SAFE (same-tx reads, trivially consistent) |
| (N12) | `_emitDailyWinningTraits` level-1 path | SAFE (same-tx reads, consistent) |
| (N13) | `runBafJackpot` + `runRewardJackpots` + `runDecimatorJackpot` consistency | SAFE (single-tx orchestration; dailyIdx invariant holds) |
| (N14) | Constructor `dailyIdx = currentDay` initialization | SAFE (benign empty-slot read short-circuits) |

**Phase 287 N-* collateral closure note.** Phase 287 zero-day-hunter follow-up flagged N-5 (boundary-race amplifier) + N-9 (NORMAL/COMPRESSED mode partial exposure) as folded-into-F-41-03 envelope. Per re-pass N-7 + N-5 above, both **NOW FULLY CLOSED** under Phase 288's dailyIdx semantic. The fix is mode-independent (NORMAL / COMPRESSED / TURBO all use frozen-dailyIdx read path).

**Economic-analyst disposition (Hypotheses E1..E7 + beyond-charge B-04..B-06):**

| # | Hypothesis | Disposition | Severity |
| - | --- | --- | --- |
| (E1) | Predictability shift under dailyIdx semantic | SAFE_BY_STRUCTURAL_CLOSURE | n/a |
| (E2-a) | Catastrophy-day timing exploit | SAFE_BY_STRUCTURAL_CLOSURE | n/a |
| (E2-b) | Orphaned-day bets observation | ACCEPTED_DESIGN | INFO (launch comms) |
| (E3) | Hero-override mechanic activation EV | FINDING_CANDIDATE | **INFO** (launch communication item — INTENDED protocol mechanic, not a bug) |
| (E4) | Reduced-scope test gap economic implications | ACCEPTED_DESIGN | INFO (test-augment scope; not v41 blocker) |
| (E5) | View function semantic revert + indexer | SAFE_BY_DESIGN | n/a |
| (E6) | Net jackpot incentive structure post-fix | NEGATIVE_RESULT_ONLY (no rebalancing) | n/a |
| (E7) | Phase 287 JPSURF residual coverage | SAFE_BY_STRUCTURAL_CLOSURE | n/a |
| (B-04) | MEV around `_unlockRng` timing | SAFE (deterministic stage machine; no MEV surface) | n/a |
| (B-05) | Sandwich attacks on degenerette bets | SAFE (no sandwich vector; wager war is intended price-discovery) | n/a |
| (B-06) | Whale coordination across multiple addresses | ACCEPTED_DESIGN (intended strategic depth) | n/a |

**E3 — Hero-Override Mechanic Activation EV (INFO-tier launch-comms note).** The hero-override mechanic, correctly fired post-Phase-288, enables a whale with concentrated trait holdings to lock a (quadrant, symbol) for the next jackpot at a cost of MIN_BET_ETH (~0.005 ETH) per quadrant. EV depends on the whale's trait concentration + daily pool size + bucket share; on a 10 ETH daily pool with ~25% bucket shares and concentrated holdings, EV >> cost. **This is the INTENDED strategic depth of the degenerette mechanic; not a bug.** Phase 288 does NOT introduce this EV; it has been the protocol's intended mechanic since pre-Phase-285. Documented under §9 "Deferred to Future Milestones" as a launch-FAQ + strategic-depth doc item. No contract change recommended.

**Re-pass severity confirmation.** F-41-01 + F-41-02 + F-41-03 all RESOLVED_AT_V41 via Phase 281 + Phase 288 structural fixes. ZERO new FINDING_CANDIDATEs from the re-pass.

### 4.4 Adversarial-Pass Roll-Up

**Adversarial-log path:** `.planning/phases/284-*/284-01-ADVERSARIAL-LOG.md` (planner-private; matches v40.0 Phase 280 + v39.0 Phase 274 + v37.0 Phase 271 precedent). Two passes documented (original + re-pass).

**Aggregate verdict:**
- Original pass: 9 of 10 hypotheses SAFE-variant; (ix) → F-41-02 ELEVATED (HIGH; closes via Phase 285 → SUPERSEDED by Phase 288).
- Phase 287 JPSURF go-nuts: 0 VIOLATIONs from per-(S, F) verdict table; F-41-03 candidate surfaced (catastrophy-tier; closes via Phase 288 collaterally).
- Re-pass on Phase 288: 0 FINDING_CANDIDATEs from all 3 skills (7 + 14 + 11 hypotheses + 3 beyond-charge); 1 INFO-tier E3 launch-comms note (not a bug).

**Severity revision (final).** F-41-01 HIGH (RESOLVED). F-41-02 HIGH with CRITICAL elevation note for `isFinalPhysicalDay_` (RESOLVED). F-41-03 MEDIUM-catastrophy-tier (RESOLVED). Zero residual FINDING_CANDIDATE.

---

## 5. Sweep Methodology + Negative-Result Attestations

Two complementary sweep methodologies executed in v41.0:

### 5a. Phase 283 SWEEP (cross-call cooperative-yield rubric)

**Sweep HEAD:** post-Phase-282 `a1212b00`. **Audit baseline:** `MILESTONE_V40_AT_HEAD_cd549499`. **Rubric:** 3-question structural attestation per SWEEP-02:
1. Within-iteration counter on the stack without storage persistence?
2. Per-call resumption regenerates identical RNG inputs?
3. `writesBudget`-equivalent cooperative-yield that could split a single conceptual operation across calls?

Three-no → SAFE-BY-STRUCTURE. Q-ii NO alone (with Q-i + Q-iii YES) is also SAFE-BY-STRUCTURE — mixing on-chain deterministic state that CHANGES BETWEEN CALLS into RNG input. **Owed-salt is the reference pattern (D-281-FIX-SHAPE-01).**

**Surface verdicts (6 surfaces enumerated):**
- Surface 1 — `processFutureTicketBatch` Path A: RESOLVED_AT_V41 via Phase 281 owed-salt; REFERENCE PATTERN annotation.
- Surface 2 — `_processOneTicketEntry` Path B: RESOLVED_AT_V41 via Phase 281 B2 symmetric.
- Surface 3 — `payDailyJackpot`/`_resumeDailyEth`/`_processDailyEth` 2-call ETH split: SAFE-BY-STRUCTURE preliminary; `_applyHeroOverride` upstream-storage observation hand-forwarded to §4 adversarial pass → surfaces F-41-02 → RESOLVED via Phase 288.
- Surface 4 — LootboxModule auto-resolve + manual resolve: SAFE-BY-STRUCTURE three-no.
- Surface 5 — BurnieCoinflip claim + daily resolution: SAFE-BY-STRUCTURE three-no.
- Surface 6 — AdvanceModule bounty + future-ticket wrapper: SAFE-BY-STRUCTURE three-no at wrapper layer.

**Outcome:** Default zero-mutation. TST-SWEEP-01 ZERO'd.

### 5b. Phase 287 JPSURF (commitment-window rubric)

**Audit HEAD:** post-Phase-286 `cef9a972`. **Posture:** FLAG-ONLY (zero contract mutations). **Per-function rubric (JPSURF-03):** for each (S ∈ READ-SET, F ∈ MUTATOR-SET) pair: (a) SAFE_BY_DESIGN if F gated on `rngLockedFlag = true`; (b) SAFE_BY_STRUCTURE if F ungated but writes to structurally-safe slot (read-write buffer / future-day-index / Phase 285 era `+1` offset); (c) VIOLATION if F ungated and mutates jackpot READ-SET slot without structural safety.

**Catalog scope:** 27 SLOAD slots in jackpot operational call graph (`dailyHeroWagers`, `traitBurnTicket`, `deityBySymbol`, `ticketQueue` far-future, `resumeEthPool`, `dailyTicketBudgetsPacked`, `level`, `jackpotCounter`, `compressedJackpotFlag`, `currentPrizePool`, `futurePrizePool`, `levelPrizePool`, `autoRebuyState`, `gameOver`, plus 13 secondary). Every external/public function across `contracts/` (DegenerusGame + 11 modules + 16 peripheral contracts) cataloged for mutated-slots + rngLockedFlag-check.

**Verdict:** **0 VIOLATIONs.** Phase 195+ read-write buffer covers ticket/mint surfaces. Phase 285 era `+1` covered hero-wagers (later structurally restored by Phase 288 dailyIdx anchor — same closure mechanism, simpler restructure). **3 residuals flagged for user review:** F-41-03 candidate (CLOSED collaterally by Phase 288); zero-day-hunter N-5 boundary-race amplifier (CLOSED by Phase 288 N-7); zero-day-hunter N-9 NORMAL/COMPRESSED mode partial exposure (CLOSED by Phase 288 N-5/N-7).

**JPSURF-04 sub-check:** `rngLockedFlag = true` set AT `vrfCoordinator.requestRandomWords()` at `AdvanceModule:1100` (not after); no frontrun gap.

### 5c. Sweep Methodology Summary

Two complementary rubrics applied at v41.0 give independent attestation: Phase 283 SWEEP rubric is per-surface (cooperative-yield mechanism + 3-Q structural analysis); Phase 287 JPSURF rubric is per-function-per-slot (commitment-window invariant + per-(S, F) verdict table). The combination is exhaustive: any cross-call determinism breakage either has a yielding surface (Phase 283 catches) or has an external mutator on a jackpot READ-SET slot (Phase 287 catches). Both rubrics CONVERGED on the same vector at Phase 287 (F-41-03 candidate) which collaterally closed F-41-02 + F-41-03 via the Phase 288 dailyIdx structural fix.

**Reference patterns established:**
- **D-281-FIX-SHAPE-01 owed-salt:** when Q-i + Q-iii both YES with Q-ii also YES, attack Q-ii by mixing on-chain deterministic state CHANGING BETWEEN CALLS into RNG input.
- **D-288-FIX-SHAPE-01 dailyIdx anchor:** for cross-call read-set slots that need to be frozen across the rng-lock window, anchor on a slot mutated only by stage-machine-driven end-of-cycle gates (single-writer rule).

---

## 6. KI Gating Walk + KNOWN-ISSUES.md Re-Verification

### 6a. Non-Promotion Ledger

| Candidate | Source | D-09 predicates failed | Verdict |
| --- | --- | --- | --- |
| F-41-01 (mint-batch determinism) | §4.0 | All 3 predicates fail (was bug; player-reachable determinism break; structurally eliminated) | NOT KI-eligible; documented in §4 + §9 per D-281-KI-01 |
| F-41-02 (hero-override within-day) | §4.0a | All 3 predicates fail | NOT KI-eligible; documented in §4 + §9 |
| F-41-03 (hero-override cross-day) | §4.0b | All 3 predicates fail | NOT KI-eligible; documented in §4 + §9 |

### 6b. KI Envelope Re-Verifications

| KI envelope | v40 state | v41 RE_VERIFIED state | Grep evidence |
| --- | --- | --- | --- |
| EXC-01 (affiliate-roll RNG substitution) | NARROWS-scoped | RE_VERIFIED-NEGATIVE-scope at v41 | `grep -rn "affiliate" contracts/modules/DegenerusGameMintModule.sol contracts/modules/DegenerusGameJackpotModule.sol contracts/modules/DegenerusGameDegeneretteModule.sol` returns 0 |
| EXC-02 (prevrandao fallback) | NARROWS-scoped | RE_VERIFIED-NEGATIVE-scope at v41 | `grep -rn "prevrandao" contracts/modules/DegenerusGameMintModule.sol contracts/modules/DegenerusGameJackpotModule.sol` returns 0 |
| EXC-03 (F-29-04 mid-cycle substitution) | NARROWS-scoped | RE_VERIFIED-NEGATIVE-scope at v41 | v41 patches don't touch gameover-RNG-substitution surface |
| EXC-04 (EntropyLib XOR-shift PRNG) | STRUCTURALLY ELIMINATED at v40 Phase 278 (entry REMOVED) | PRESERVED at v41 | `grep -rn "EntropyLib.entropyStep" contracts/` returns 0 |

### 6c. Verdict Summary

KNOWN-ISSUES.md is **UNMODIFIED** at v41 close per D-281-KI-01.
- Zero entries added (all three F-41-NN shipped-then-fixed defects documented in §4 + §9, not KI — per D-281-KI-01 precedent).
- Zero entries removed (EXC-04 removed at v40 close per D-280-EXC04-01; EXC-01..03 unchanged).

Closure verdict: `0 of 0 KI_ELIGIBLE_PROMOTED; KNOWN_ISSUES_UNMODIFIED`.

---

## 7. Carry-Forward Decision Anchors

Locked decisions across the v25..v41 audit chain governing v41.0 close.

### 7.1 v41.0 Decision Anchors (LOCKED at v41 close)

**Phase 281:**
- **D-281-FIX-SHAPE-01** — owed-salt 4th keccak input. REFERENCE PATTERN for SWEEP rubric.
- **D-281-STARTINDEX-SEMANTICS-01** — `TraitsGenerated.startIndex` carries `owed_at_call_entry`. ABI shape unchanged.
- **D-281-FIX01-REFRAME-01** — FIX-01 W2 indexer-replay primary wording.
- **D-281-SEVERITY-01** — F-41-01 HIGH per D-08.
- **D-281-KI-01** — KNOWN-ISSUES.md UNMODIFIED.

**Phase 282:**
- **D-282-ASSERTION-FRAME-01** — TST-FIX-01 + TST-FIX-06 W2 indexer-replay primary.
- **D-282-PREFIX-BRANCH-01** — DROPPED per user re-scope 2026-05-16.
- **D-282-GAS-EMPIRICAL-01** — DOWNGRADED to informational.
- **D-282-B2-COVERAGE-01** — TST-FIX-01..06 cover both drain paths.

**Phase 283:**
- **D-283-SCOPE-01** — 6 cooperative-yield surfaces enumerated.
- **D-283-SWEEP04-01** — jackpot 2-call ETH split SAFE-BY-STRUCTURE preliminary CONFIRMED via 5-trace; `_applyHeroOverride` cross-day observation hand-forwarded.
- **D-283-MINT-REFROW-01** — mint-batch reference-defect row format in SWEEP-LOG.
- **D-283-RESEARCH-AGENT-01** — plan-phase skipped research-agent.

**Phase 285 (SUPERSEDED-BY-PHASE-288):**
- **D-285-FIX-SHAPE-01** — write-side `+1` Approach B chosen at Phase 285 plan-phase; **SUPERSEDED at Phase 288** by structural read-side `dailyIdx` anchor.
- **D-285-EVIDENCE-CLASS-01** — F-41-02 evidence class ALGORITHM_VERIFIED.

**Phase 286 (REVISED-AT-PHASE-289):**
- **D-286-FIXTURE-SCOPE-01** — TST-HOFIX-01..04; TST-HOFIX-05 ZERO'd (HOFIX-AUDIT default 1-surface outcome).

**Phase 287 (JPSURF FLAG-ONLY):**
- **D-287-POSTURE-01** — FLAG-ONLY per user instruction 2026-05-17; 0 contract mutations; findings cataloged.
- **D-287-FINDINGS-01** — 0 VIOLATIONs from per-(S, F) verdict table; F-41-03 candidate + 2 zero-day-hunter follow-up residuals flagged.

**Phase 288:**
- **D-288-FIX-SHAPE-01** — dailyIdx-anchor read-side fix (supersedes Phase 285 write-side `+1`; collaterally restores canonical bet-write semantic). REFERENCE PATTERN for cross-call read-set frozen-during-window slots.

**Phase 289:**
- **D-289-COVERAGE-01** — TST-JPSURF-01..04 cross-day regression + TST-HOFIX-01..04 adjustments to post-Phase-288 canonical semantic. 9 tests PASS.

**Phase 284 (TERMINAL):**
- **D-284-SEVERITY-01** — F-41-01..03 severities locked: HIGH/HIGH(CRIT)/MEDIUM.
- **D-284-KI-01** — KNOWN-ISSUES.md UNMODIFIED (carry from D-281-KI-01).
- **D-284-ADVERSARIAL-CHARGE-01** — original 10-hypothesis charge.
- **D-284-ADVERSARIAL-RE-PASS-01** — re-pass on Phase 288 fix.
- **D-284-CLOSURE-01** — atomic ROADMAP + STATE + MILESTONES + PROJECT + REQUIREMENTS closure flip; signal `MILESTONE_V41_AT_HEAD_315978a0c18294e0d7fa5cd4cdfe7f8e5b9a95c4` at §9c.
- **D-284-FCITE-01** — terminal-phase zero forward-cite emission.
- **D-284-ADVERSARIAL-SCOPE-01** — 3-skill PARALLEL spawn orchestrator-dispatched.

### 7.2 v40+ Chain Carries (preserved at v41 close)

- **D-40N-MINTBOOST-OUT-01** (v40) — mint-boost path retention at v41 close.
- **D-40N-FILES-01 → D-41N-FILES-01** — single canonical audit deliverable per milestone.
- **D-40N-CLOSURE-01 → D-41N-CLOSURE-01** — atomic closure flip pattern.
- **D-40N-LBX02-OUT-01** — LBX-02 fixture-coverage gap RE-DEFERRED.
- **D-274-AUTORESOLVE-OUT-01** (v39) — auto-resolve lootbox path retirement deferred.
- **D-271-ADVERSARIAL-01 + D-271-ADVERSARIAL-02 + D-271-ADVERSARIAL-03** (v37) — 3-skill PARALLEL; `/degen-skeptic` OUT OF SCOPE.
- **D-08** (v25 carry) — 5-Bucket Severity Rubric.
- **D-09** (v25 carry) — KI Gating Rubric.
- **D-NN-FCITE-01 → D-41N-FCITE-01** — terminal-phase zero forward-cite emission.

---

## 8. Process Notes

### Commit cadence + approval discipline

- **Phase 281:** 1 USER-APPROVED batched contract commit `221afcf7`. Design-intent trace landed BEFORE patch per FIX-05.
- **Phase 282:** 1 USER-APPROVED batched test commit `a1212b00`. Reduced-scope user authorization 2026-05-16.
- **Phase 283:** 0 USER-APPROVED contract/test commits (default zero-mutation outcome).
- **Phase 285:** 1 USER-APPROVED batched contract commit `c4d62564`. SUPERSEDED-AT-PHASE-288 (Phase 288 reverts the bytecode).
- **Phase 286:** 1 USER-APPROVED batched test commit `cef9a972`. REVISED-AT-PHASE-289.
- **Phase 287:** 0 USER-APPROVED contract/test commits per FLAG-ONLY user posture.
- **Phase 288:** 1 USER-APPROVED batched contract commit `4837fa5c`. Structural fix supersedes Phase 285; closes F-41-02 + F-41-03 collaterally.
- **Phase 289:** 1 USER-APPROVED batched test commit `ab76e990`. 9 tests PASS.
- **Phase 284 (this phase, TERMINAL):** SOURCE-TREE FROZEN — zero `contracts/` + zero `test/` mutations. AGENT-COMMITTED audit deliverable + planning artifacts + closure-flip docs per terminal-phase invariant.

### Supersede pattern (Phase 285 → Phase 288 elegant restructure)

v41.0 demonstrates the supersede pattern in audit-driven contract development. Phase 285 chose Approach B (write-side `+1`) per D-285-FIX-SHAPE-01 to close F-41-02's intra-day window structurally. The fix worked correctly for the within-day case but did NOT cover the cross-day catastrophy case (F-41-03) because both call sites still re-evaluated `_simulatedDayIndex()` LIVE. Phase 287 JPSURF go-nuts commitment-window audit surfaced F-41-03 as a residual. Phase 288 restructured the fix to the read side via the `dailyIdx` anchor (Approach R3-equivalent), simultaneously closing BOTH F-41-02 AND F-41-03 via the single-writer dailyIdx invariant. The net contract state at v41 close = Phase 288 canonical (Phase 285 contributes zero bytes net; Phase 285 view-fn NatSpec also reverted). Process lesson: when an initial fix iteration covers only part of a finding's surface, the audit's commitment-window rubric (Phase 287) surfaces residuals; a structural restructure (Phase 288) may close MORE than the initial fix at LOWER bytecode cost (Phase 288 net −36 bytes vs Phase 285's write-side `+1` overhead). The supersede pattern is documented per `feedback_no_history_in_comments.md` (in audit prose, not contract comments — contracts at v41 close describe what IS, no history of supersession in NatSpec).

### Two-pass adversarial discipline

Phase 284 ran the 3-skill PARALLEL adversarial pass TWICE:
1. **Original pass** on the post-Phase-282 finished §4 draft: surfaced (ix) `_applyHeroOverride` cross-day vector → ELEVATED_TO_FINDING F-41-02 by 3-of-3 consensus.
2. **RE-PASS** on the Phase 288 dailyIdx fix: 0 FINDING_CANDIDATEs across all 3 skills (7 + 14 + 11 hypotheses + 3 beyond-charge); 1 INFO-tier launch-comms note (E3 — not a bug).

This is consistent with the v37/v38/v39/v40 3-skill PARALLEL adversarial pass discipline per D-271-ADVERSARIAL-01 + D-271-ADVERSARIAL-03 carry; the TWICE-execution shape is novel to v41.0 and warranted by the Phase 285→288 supersede chain (the initial pass red-teamed Phase 281+282; a re-pass was required to red-team the Phase 288 structural restructure that closed the residual surfaced at the initial pass).

### Broad-scope JPSURF per user catastrophy-scenario hunt instruction

Per user instruction 2026-05-17, Phase 287 ran in GO-NUTS POSTURE — catastrophy-level edge cases (e.g., "nobody calls advanceGame for a day; day rolls between CALL 1 and CALL 2") explicitly in-scope even when economic likelihood is LOW. This is what surfaced F-41-03 (cross-day catastrophy case). The economic likelihood under healthy operation is LOW but per Phase 287 §5 economic-likelihood envelope: "INEVITABLE under catastrophic stall." Phase 288's structural fix eliminates the vector regardless of likelihood, ensuring the protocol behavior is correct in both healthy and catastrophy regimes.

---

## 9. Milestone Closure Attestation

### 9a. Verdict Distribution

- **Severity counts:** 3 F-41-NN total. F-41-01 HIGH RESOLVED_AT_V41 (first non-zero F-NN finding milestone in v25..v41; mint-batch determinism). F-41-02 HIGH with CRITICAL elevation note RESOLVED_AT_V41 (hero-override within-day; surfaced by 3-skill PARALLEL adversarial consensus on Phase 283 hand-forward observation; closed via Phase 285 → SUPERSEDED by Phase 288 structural). F-41-03 MEDIUM-catastrophy-tier RESOLVED_AT_V41 (hero-override cross-day; surfaced by Phase 287 JPSURF go-nuts audit; closed collaterally via Phase 288 dailyIdx anchor).
- **KI eligibility:** 0 of 0 KI_ELIGIBLE_PROMOTED. All 3 findings fail D-09 predicates (bugs, player-reachable, structurally eliminated). Documented in §4 + §9 per D-281-KI-01 precedent.
- **KNOWN-ISSUES.md disposition:** UNMODIFIED (no entries added or removed at v41 close).
- **Adversarial-pass result:** 3-skill PARALLEL `/contract-auditor` + `/zero-day-hunter` + `/economic-analyst` consensus. Original pass: F-41-02 ELEVATED. Re-pass on Phase 288: 0 residual FINDING_CANDIDATEs; 1 INFO-tier E3 launch-comms note. All 3 F-41-NN RESOLVED.
- **Regression appendix:** REG-01 PASS (v40.0 closure NON-WIDENING) + REG-02 PASS (v34.0 closure NON-WIDENING) + REG-03 KI envelope re-verifications (3 RE_VERIFIED-NEGATIVE-scope + 1 STRUCTURALLY ELIMINATED preserved) + REG-04 prior-finding spot-check sweep PASS across `audit/FINDINGS-v25..v40.0.md` for v41-touched surface set.

**Closure-verdict math:** `3 of 3 F-41-NN RESOLVED_AT_V41 (F-41-01 mint-batch + F-41-02 hero-override within-day + F-41-03 hero-override cross-day); 0 of 0 KI_ELIGIBLE_PROMOTED; KNOWN_ISSUES_UNMODIFIED`.

### 9b. 9-Phase Wave Summary

| Phase | Type | Commits | Requirements satisfied | Outcome |
| --- | --- | --- | --- | --- |
| Phase 281 — FIX (mint-batch) | Contract | 1 USER-APPROVED (`221afcf7`) | FIX-01..05 (5/5) | Owed-salt seed mix; B2 symmetric; zero storage delta; +17 bytes |
| Phase 282 — TST-FIX (mint-batch) | Test | 1 USER-APPROVED (`a1212b00`) | TST-FIX-01..04 (4/4 + 2 dropped per re-scope) | W2 indexer-replay; ALGORITHM_VERIFIED |
| Phase 283 — SWEEP | Analytical | 0 (default zero-mutation) | SWEEP-01..05, TST-SWEEP-01 (6/6) | 6 surfaces SAFE-BY-STRUCTURE; hand-forward observation → F-41-02 |
| Phase 285 — HOFIX (SUPERSEDED) | Contract | 1 USER-APPROVED (`c4d62564`) | HOFIX-AUDIT-01..05, FIX-HOFIX-01 (5/5) | Write-side `+1`; **SUPERSEDED-AT-PHASE-288** |
| Phase 286 — TST-HOFIX (REVISED) | Test | 1 USER-APPROVED (`cef9a972`) | TST-HOFIX-01..04 (4/4; TST-HOFIX-05 zeros out) | **REVISED-AT-PHASE-289** to post-Phase-288 canonical |
| Phase 287 — JPSURF (FLAG-ONLY) | Analytical | 0 (FLAG-ONLY posture) | JPSURF-01..05 (5/5) | 0 VIOLATIONs; F-41-03 candidate flagged |
| Phase 288 — FIX-JPSURF | Contract | 1 USER-APPROVED (`4837fa5c`) | FIX-JPSURF-01 (1/1) | dailyIdx structural fix; supersedes Phase 285; F-41-02 + F-41-03 RESOLVED; net −36 bytes |
| Phase 289 — TST-JPSURF | Test | 1 USER-APPROVED (`ab76e990`) | TST-JPSURF-01..04 + TST-HOFIX-01..04 adjustments | 9 tests PASS; ALGORITHM_VERIFIED for F-41-03 |
| Phase 284 — TERMINAL | Audit deliverable | 1 AGENT-COMMITTED closure-flip | AUDIT-01..08, REG-01..04 (12/12) | This deliverable; 3-skill RE-PASS 0 FINDING_CANDIDATEs |
| **Total** | — | 6 USER-APPROVED + 1 AGENT-COMMITTED closure | 43/43 | 3 RESOLVED_AT_V41; KI UNMODIFIED; closure signal emitted §9c |

### 9c. Closure Signal

**Signal:** `MILESTONE_V41_AT_HEAD_315978a0c18294e0d7fa5cd4cdfe7f8e5b9a95c4`

The closure signal `MILESTONE_V41_AT_HEAD_315978a0c18294e0d7fa5cd4cdfe7f8e5b9a95c4` per D-284-CLOSURE-01 + D-41N-CLOSURE-01 carry of D-40N-CLOSURE-01 / D-274-CLOSURE-01 chain is emitted at the Phase 284 terminal closure-flip commit. The `<sha>` placeholder above resolves to the closure-flip commit SHA at commit-time and is backfilled across 5 verbatim FINDINGS locations + 3 cross-document propagation targets per the standard pattern.

**5 FINDINGS verbatim locations:**
1. Frontmatter `closure_signal: MILESTONE_V41_AT_HEAD_315978a0c18294e0d7fa5cd4cdfe7f8e5b9a95c4`
2. Frontmatter `audit_subject_head: "<sha>"` (this represents the closure-flip commit which is itself the v41 close HEAD)
3. §1 Audit Subject + Baseline (introductory paragraph)
4. §9b table closing row ("closure signal emitted §9c")
5. §9c (this block)

**3 cross-document propagation targets:**
1. `.planning/ROADMAP.md` — Phase 284 flipped to `[x]`; v41.0 milestone summary cites closure signal.
2. `.planning/STATE.md` — Last Shipped Milestone block updated with v41.0 entry citing closure signal.
3. `.planning/MILESTONES.md` — v41.0 archive entry with closure signal + 9-phase shape + `3 of 3 F-41-NN RESOLVED_AT_V41`.

(PROJECT.md + REQUIREMENTS.md are atomic-flip companions per D-284-CLOSURE-01.)

### 9.NN Commit-Readiness Register

#### 9.NN.i USER-APPROVED contracts

- `221afcf7` (Phase 281) — mint-batch determinism fix via owed-salt seed mix [FIX-01..05] (B2 symmetric).
- `c4d62564` (Phase 285) — hero-override day-index fix via write-side +1 offset [FIX-HOFIX-01]. **SUPERSEDED-AT-PHASE-288.**
- `4837fa5c` (Phase 288) — F-41-03 cross-day determinism fix via dailyIdx read; supersede Phase 285 [FIX-JPSURF-01].

#### 9.NN.ii USER-APPROVED tests

- `a1212b00` (Phase 282) — multi-call drain trait-byte-identity + non-increasing 4th-field + pairwise-distinct keccak inputs + single-call byte-identity [TST-FIX-01..04] (REDUCED SCOPE per 2026-05-16 user authorization).
- `cef9a972` (Phase 286) — hero-override day-index regression fixture [TST-HOFIX-01..04] (TST-HOFIX-05 zeros out). **REVISED-AT-PHASE-289.**
- `ab76e990` (Phase 289) — adjust Phase 286 tests + F-41-03 cross-day regression [TST-JPSURF-01..04].

#### 9.NN.iii AGENT-COMMITTED audit + planning artifacts (Phase 284 terminal)

- `audit/FINDINGS-v41.0.md` (this deliverable) — FINAL READ-only (chmod 444) at v41.0 closure HEAD.
- `.planning/phases/284-delta-audit-findings-consolidation-terminal/284-01-ADVERSARIAL-LOG.md` + 6 adversarial-pass reports (3 original + 3 re-pass).
- `.planning/ROADMAP.md` + `.planning/STATE.md` + `.planning/MILESTONES.md` + `.planning/PROJECT.md` + `.planning/REQUIREMENTS.md` — atomic closure-flip per D-284-CLOSURE-01.

### Deferred to Future Milestones

Per D-284-FCITE-01 (terminal-phase zero forward-cite emission): the following items are deferred via locked-decision IDs + descriptive labels only — no post-v41 milestone references emitted.

- **D-281-FIX-SHAPE-01 owed-salt reference pattern** — future cooperative-yield mechanisms encountering analogous defects should adopt owed-salt as SWEEP rubric reference solution when Q-i + Q-iii both YES with Q-ii also YES.
- **D-288-FIX-SHAPE-01 dailyIdx-anchor reference pattern** — future cross-call read-set frozen-during-window requirements should adopt the single-writer-end-of-cycle-gate anchor pattern.
- **D-40N-MINTBOOST-OUT-01 mint-boost retention** — `_queueTicketsScaled` + `_rollRemainder` + `rem` byte retained at v41 close.
- **D-274-AUTORESOLVE-OUT-01 auto-resolve lootbox path retirement** — carry-forward.
- **LBX-02 fixture-coverage gap** — fixture-coverage gap persists; analytical worst-case load-bearing per Phase 266 GAS-01.
- **Superseded-baseline SURF `it.skip` cleanup** — v41 introduces new superseded-baseline SURF rows; backlog cleanup task.
- **Indexer-side migration handoff** — off-chain indexers must update trait-reconstruction logic to use the new keccak input set (4th positional `owed_at_call_entry`) and update `dailyHeroWagers` reconstruction to use `getDailyHeroWager(D)` = "bets placed on day D" canonical semantic (per Phase 288 view-fn NatSpec restoration). Optional event-layer enhancement: add `uint32 sourceDay = dailyIdx` field to `DailyWinningTraits` to make event-vs-storage indexer reconciliation explicit during stalls (per zero-day-hunter re-pass N9). Out of repo scope; user handles post-deploy of Phase 288 fix.
- **Hero-override mechanic activation launch FAQ (E3 from economic-analyst re-pass, INFO-tier)** — add user-facing documentation explaining: (a) MIN_BET_ETH cost (~0.005 ETH) to lock a (quadrant, symbol) for next jackpot; (b) the trait-holding prerequisite for EV extraction; (c) per-day independence of the mechanic. Optional UX item: expose `traitBurnTicket[lvl][trait].length` view function for pool concentration self-assessment. Per economic-analyst E3: NOT a bug, the INTENDED protocol mechanic; deserves explicit user communication so non-whale players understand strategic asymmetry.
- **Orphaned-day bets UX disclosure (E2-b from economic-analyst re-pass, INFO-tier)** — under multi-day stall, bets placed on intermediate days whose `dailyIdx` is never latched are economically orphaned. Document in user-facing copy as "placing a degenerette ETH bet is best-effort under stalled gameplay."
- **Launch-posture KI policy** — "how to record shipped-then-fixed bugs in KI" deferred until launch posture review per D-281-KI-01 rationale. v41 sets the precedent (FINDINGS §4 + §9 documentation; KI UNMODIFIED).
- **Path-accumulator divergence documentation** — Phase 282 SUMMARY.md noted Path A `processed += take` vs Path B `processed += writesUsed >> 1` pre-existing contract quirk. Future indexer-reference helper milestone may document.

---

*Phase: 284-delta-audit-findings-consolidation-terminal*
*Plan: 01*
*Milestone: v41.0 (FIRST MULTI-FINDING MILESTONE in v25..v41 audit history — 3 of 3 F-41-NN RESOLVED_AT_V41)*
*Status: FINAL — READ-ONLY (chmod 444) at v41.0 closure HEAD*
*Closure signal: `MILESTONE_V41_AT_HEAD_315978a0c18294e0d7fa5cd4cdfe7f8e5b9a95c4` (resolved at the Phase 284 closure-flip commit per D-284-CLOSURE-01)*
*9 phases: 281 FIX + 282 TST-FIX + 283 SWEEP + 285 HOFIX (SUPERSEDED) + 286 TST-HOFIX (REVISED) + 287 JPSURF (FLAG-ONLY) + 288 FIX-JPSURF + 289 TST-JPSURF + 284 TERMINAL*
*Requirements: 43/43 satisfied (5 FIX + 4 TST-FIX [2 reduced-scope] + 6 SWEEP/TST-SWEEP + 5 HOFIX-AUDIT + 1 FIX-HOFIX + 4 TST-HOFIX + 5 JPSURF + 1 FIX-JPSURF + 4 TST-JPSURF + 12 AUDIT/REG)*
*Findings: 3 F-41-NN ALL RESOLVED_AT_V41 — F-41-01 (mint-batch HIGH) + F-41-02 (hero-override within-day HIGH with CRITICAL elevation) + F-41-03 (hero-override cross-day MEDIUM-catastrophy-tier)*
*Adversarial-pass: 3-skill PARALLEL TWICE (original on Phase 281+282 §4 + re-pass on Phase 288 fix); `/contract-auditor` + `/zero-day-hunter` + `/economic-analyst`; `/degen-skeptic` OUT OF SCOPE; orchestrator-dispatched per D-284-ADVERSARIAL-SCOPE-01 + D-284-ADVERSARIAL-RE-PASS-01*
