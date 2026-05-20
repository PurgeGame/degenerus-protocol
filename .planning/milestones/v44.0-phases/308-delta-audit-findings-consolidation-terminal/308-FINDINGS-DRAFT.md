---
phase: 308-delta-audit-findings-consolidation-terminal
plan: 01
milestone: v44.0
milestone_name: sStonk Per-Day Redemption Refactor + Accounting Invariant Proof
audit_baseline: 8111cfc5189f628b64b500c881f9995c3edf0ed2
audit_baseline_signal: MILESTONE_V43_AT_HEAD_8111cfc5189f628b64b500c881f9995c3edf0ed2
v42_baseline: 81d7c94bc924edb3429f6dc16ee33280fc11c7c2
v42_baseline_signal: MILESTONE_V42_AT_HEAD_81d7c94bc924edb3429f6dc16ee33280fc11c7c2
v41_baseline: 315978a0c18294e0d7fa5cd4cdfe7f8e5b9a95c4
v41_baseline_signal: MILESTONE_V41_AT_HEAD_315978a0c18294e0d7fa5cd4cdfe7f8e5b9a95c4
user_approved_contract_commit: 213f9184
audit_subject_head: "6f0ba2963a10654ba554a8c333c5ee80c54a8349"
closure_signal: MILESTONE_V44_AT_HEAD_6f0ba2963a10654ba554a8c333c5ee80c54a8349
deliverable: audit/FINDINGS-v44.0.md
requirements: [AUDIT-01, AUDIT-02, AUDIT-03, AUDIT-04, AUDIT-05, AUDIT-06, AUDIT-07, AUDIT-08, AUDIT-09,
               REG-01, CLS-01, CLS-02,
               INV-01, INV-02, INV-03, INV-04, INV-05, INV-06, INV-07, INV-08, INV-09, INV-10, INV-11, INV-12, INV-13,
               SPEC-01, SPEC-02, SPEC-03, SPEC-04, SPEC-05,
               IMPL-01, IMPL-02, IMPL-03, IMPL-04,
               TST-01, TST-02, TST-03, TST-04, TST-05, TST-06, TST-07,
               EDGE-01, EDGE-02, EDGE-03, EDGE-04, EDGE-05, EDGE-06, EDGE-07, EDGE-08, EDGE-09, EDGE-10,
               EDGE-11, EDGE-12, EDGE-13, EDGE-14, EDGE-15, EDGE-16, EDGE-17, EDGE-18, EDGE-19, EDGE-20,
               SWP-01, SWP-02, SWP-03, SWP-04, SWP-05]
phase_status: COMPLETE
phase_count: 5
phase_ids: [304, 305, 306, 307, 308]
phase_shape: spec + impl + tst + sweep + terminal
requirements_total: 63
inv_count_actual: 13
edge_count_actual: 20
inv_count_roadmap_template: 12
edge_count_roadmap_template: 18
findings_total: 0
sstonk_violations_resolved: 7
sstonk_violations_total: 7
invariants_proven: 13
edge_cases_tested: 20
new_findings: 0
known_issues_disposition: UNMODIFIED
adversarial_pass_skills: [contract-auditor, zero-day-hunter, economic-analyst]
adversarial_pass_outcome: "unanimous-NEGATIVE — 72/72 disposition rows; 0 FINDING_CANDIDATE; 3 SAFE_BY_DESIGN; Task 6 elevation gate SKIPPED"
out_of_scope_skills: [degen-skeptic]
v45_handoff_register_total: 135
v45_handoff_register_breakdown: "112 D-43N-V44-HANDOFF-NN (HANDOFF-01..110 + HANDOFF-118..119; excludes HANDOFF-111..117 closed by v44) + 22 D-43N-V44-ADMA-NN + 1 D-43N-V44-ADMA-ERRATUM-01"
supersedes: [v43.0]
status: "FINAL — READ-ONLY"
read_only: true
generated_at: "2026-05-20T01:27:58-05:00"
---

# v44.0 Findings — sStonk Per-Day Redemption Refactor + Accounting Invariant Proof (Terminal; FIX-MILESTONE)

## 1. Audit Subject + Baseline

**Audit Baseline.** The audit baseline is v43.0 closure HEAD `8111cfc5189f628b64b500c881f9995c3edf0ed2` (closure signal `MILESTONE_V43_AT_HEAD_8111cfc5189f628b64b500c881f9995c3edf0ed2` carry-forward from `audit/FINDINGS-v43.0.md` §9c). v44.0 closure HEAD is `6f0ba2963a10654ba554a8c333c5ee80c54a8349` (resolved at Phase 308 Commit 1 per `D-44N-CLOSURE-01` 2-commit sequential SHA orchestration; see §9c for the emitted `MILESTONE_V44_AT_HEAD_6f0ba2963a10654ba554a8c333c5ee80c54a8349` signal). v42 chain reference: `MILESTONE_V42_AT_HEAD_81d7c94bc924edb3429f6dc16ee33280fc11c7c2`. v41 chain reference: `MILESTONE_V41_AT_HEAD_315978a0c18294e0d7fa5cd4cdfe7f8e5b9a95c4`.

**5-Phase Wave Shape (FIX-MILESTONE spec + impl + tst + sweep + terminal).** Phases 304 (SPEC + Invariant Model) + 305 (IMPL — the v44.0 sStonk per-day redemption refactor) + 306 (TST — Foundry invariant + fuzz coverage) + 307 (SWEEP — 3-skill HYBRID adversarial pass) + 308 (TERMINAL — this deliverable; SOURCE-TREE FROZEN). Per `D-44N-CLOSURE-01`, the v44.0 milestone is a FIX-MILESTONE: ONE USER-APPROVED `contracts/` commit (`213f9184` at Phase 305 IMPL) lands the actual remediation; every other commit across the envelope is AGENT-COMMITTED test/audit/planning per `feedback_no_contract_commits.md` + `D-43N-TEST-COMMITS-AUTO-01` (only mainnet `.sol` files require explicit user approval).

**1 Audit-Subject Surface (sStonk per-day redemption refactor).** The v44.0 refactor replaces the single-pool `redemptionPeriodIndex` counter with per-day-keyed `pendingByDay[uint32]` storage and a `pendingResolveDay` sentinel that enforces an at-most-one-unresolved-day single-pool invariant (INV-13). This structurally closes the V-184 cross-day re-roll CATASTROPHE (RNGLOCK-FIXREC §103; HANDOFF-111) and the 6 catalog rows it subsumes (HANDOFF-112..117). The same three exempt entry points carry forward from v43.0 (`advanceGame()` + reachable; VRF coordinator callback; `retryLootboxRng()` failsafe per `D-42N-RETRY-RNG-DOMAIN-SEP-01` Option A); the per-day refactor introduces exactly one new sStonk-specific exempt writer (`resolveRedemptionPeriod` writing `redemptionPeriods[day].roll`), enumerated in §3.B.

**Write Policy.** AGENT-COMMITTED throughout the v44.0 envelope EXCEPT the single USER-APPROVED contract commit `213f9184 feat(305-01): v44.0 sStonk per-day redemption refactor — 1-slot DayPending + INV-13 sentinel` per `feedback_batch_contract_approval.md` + `feedback_never_preapprove_contracts.md`. The 6 Phase 306 test commits landed AGENT-COMMITTED per `D-43N-TEST-COMMITS-AUTO-01`. Phase 308 contributes 2 AGENT-COMMITTED commits per `D-44N-CLOSURE-01` 2-commit sequential SHA orchestration pre-authorized per `D-44N-CLOSURE-PREAUTH-01`. KNOWN-ISSUES.md is **UNMODIFIED** at v44 close per `D-44N-KI-01`.

**SOURCE-TREE FROZEN.** Phase 308 contributes zero `contracts/` and zero `test/` mutations. Only `audit/FINDINGS-v44.0.md` + the planner-private artifact bundle (`.planning/phases/308-.../*`) + the 5 closure-flip docs (`ROADMAP.md` / `STATE.md` / `MILESTONES.md` / `PROJECT.md` / `REQUIREMENTS.md`) are committed at this phase.

---

## 2. Executive Summary

### Closure Verdict Summary

- **AUDIT-01:** §3.A delta-surface table aggregates the v44.0 commit envelope into 8 load-bearing rows per `D-308-DELTA-SURFACE-DEPTH-01` — row 2 is the single USER-APPROVED `contracts/` commit `213f9184`; the 7 other rows aggregate the Phase 304 SPEC bundle + Phase 305 planning bundle + Phase 306 TST Plans 01-05 + Phase 307 SWEEP LOG bundle + the Phase 308 SOURCE-TREE FROZEN attestation. `git log --no-merges 8111cfc5..HEAD --oneline -- contracts/ test/` returns exactly 1 `contracts/` commit (`213f9184`) + 6 `test/` commits.
- **AUDIT-02:** §3.B per-exempt-entry-point attestation matrix — the 3 exempt entry points (EXEMPT-ADVANCEGAME + EXEMPT-VRFCALLBACK + EXEMPT-RETRYLOOTBOXRNG) carry forward from v43.0 §3.B; the v44 per-day refactor inserts ONE new sStonk-specific row inside EXEMPT-ADVANCEGAME: `redemptionPeriods[day].roll` exempt writer = `resolveRedemptionPeriod` (`StakedDegenerusStonk.sol:633`), reachable only from `advanceGame()` via `DegenerusGameAdvanceModule:1234/:1300/:1333`. The per-day refactor introduces no new non-exempt writer (Phase 307 SWEEP unanimous-NEGATIVE).
- **AUDIT-03:** §3.C conservation re-proof — every INV-01..13 attested as proven by a specific `invariant_INV_NN_*` fn (`test/invariant/RedemptionAccounting.t.sol`) + cross-checking `testFuzz_EDGE_NN_*` fns (`test/fuzz/RedemptionEdgeCases.t.sol`); all 13 PROVEN at FOUNDRY_PROFILE=deep (256 runs × 128 depth × 32768 calls per invariant). INV count diverges from ROADMAP template (12 → 13) per `D-308-INV-COUNT-01` (emergent INV-13 from `D-305-SENTINEL-01`).
- **AUDIT-04:** §3.D V-184 RESOLVED-AT-V44 disposition — the headline CATASTROPHE the v44 refactor closes structurally (per-day keying makes the overwrite primitive unreachable) + mechanized (INV-13 single-pool sentinel PROVEN at 256×128×32768; EDGE-07 attack-reproduction asserts no overwrite; TST-05 v43-vm.skip blocks flipped to strict byte-identity assertions PASS at v44.0 close). HANDOFF-111..117 7-row subsumption fan-out closed via single structural refactor `213f9184`.
- **AUDIT-05:** §3.E remaining v43 backlog reference — 135 anchors deferred to v45.0+ via the v43.0 §9d handoff register (142 - 7 = 135); v44.0 narrow scope (sStonk per-day refactor) consumes exactly 7 anchors (HANDOFF-111..117) and does NOT consume the remaining 135.
- **AUDIT-06:** §4 adversarial-pass disposition — Phase 307 3-skill HYBRID (`/contract-auditor` SEQUENTIAL_MAIN_CONTEXT + `/zero-day-hunter` + `/economic-analyst` HYBRID-fallback) condensed to ~17 hypothesis rows per `D-308-ADVERSARIAL-DISP-01`; full 72-row Disposition cross-referenced to `307-01-ADVERSARIAL-LOG.md`. Outcome: unanimous-NEGATIVE; 72/72 disposition rows; 0 FINDING_CANDIDATE; 3 SAFE_BY_DESIGN; Task 6 elevation gate SKIPPED; 0 skeptic-filter discards.
- **AUDIT-07:** §3.F formal invariant attestation matrix (NEW for v44.0) — 13 rows `(INV-NN, test_id, status)`; all 13 status=PROVEN; 0 WAIVED; 0 FAILING. In-band divergence-rationale attestation documents the 12→13 / 18→20 override per `D-308-INV-COUNT-01`.
- **AUDIT-08:** §6 KI walkthrough — EXC-01..03 RE_VERIFIED-NEGATIVE-scope at v44 close (v44 audit subject is the sStonk per-day refactor with zero affiliate-roll / AdvanceModule game-over-RNG-substitution interaction beyond sStonk-internal); EXC-04 STRUCTURALLY ELIMINATED preserved (grep proof `grep -rn "entropyStep" contracts/` returns ZERO matches at v44 close HEAD); KNOWN-ISSUES.md UNMODIFIED per `D-44N-KI-01`.
- **AUDIT-09:** §9 closure attestation — FIX-milestone verdict per `D-308-INV-COUNT-01` strict math: `7 of 7 SSTONK_VIOLATIONS RESOLVED_AT_V44; 13 of 13 INVARIANTS PROVEN; 20 of 20 EDGE_CASES TESTED; 0 NEW_FINDINGS; KNOWN_ISSUES_UNMODIFIED`; 5-phase wave summary; closure signal `MILESTONE_V44_AT_HEAD_6f0ba2963a10654ba554a8c333c5ee80c54a8349` propagated to 5 FINDINGS verbatim locations + 3 cross-document targets; §9d v45.0+ handoff register (135 anchors: 112 HANDOFF + 22 ADMA + 1 ERRATUM).
- **REG-01:** §5 — v43.0 closure signal `MILESTONE_V43_AT_HEAD_8111cfc5189f628b64b500c881f9995c3edf0ed2` NON-WIDENING at v44 close HEAD. Every v43.0 audit-subject surface byte-identical at v44.0 close EXCEPT the Phase 301 `vm.skip(HANDOFF-111..117)` lines flipped to strict assertions at `test/fuzz/RngLockDeterminism.t.sol:1277` (intended diff attested in §3.A row 6; Phase 306 Plan 04 `b102bc0f`). The USER-APPROVED contract diff (`213f9184`) is the only intended `contracts/` diff (attested in §3.A row 2).

### Verdict Math (per D-308-INV-COUNT-01)

- **SSTONK_VIOLATIONS resolved:** 7 of 7 (V-184 + V-186 + V-188 + V-190 + V-191 + V-192 + V-193 = HANDOFF-111..117; closed via single structural refactor `213f9184` per the FIXREC §0.6 subsumption map).
- **INVARIANTS proven:** 13 of 13 (INV-01..13 PROVEN at FOUNDRY_PROFILE=deep; INV-13 emergent per `D-305-SENTINEL-01`).
- **EDGE_CASES tested:** 20 of 20 (EDGE-01..20 PROVEN at 10k runs each; EDGE-19 transfer/multi-day-stale-claim + EDGE-20 burn-too-small dust floor extend the original 18).
- **NEW_FINDINGS:** 0 (Phase 307 unanimous-NEGATIVE; 0 FINDING_CANDIDATE).
- **KNOWN-ISSUES.md disposition:** UNMODIFIED.

### Severity Counts (per D-08 5-Bucket Rubric)

- CRITICAL: 0
- HIGH: 0
- MEDIUM: 0
- LOW: 0
- INFO: 0
- Total F-44-NN: 0 (zero NEW findings at v44; FIX-milestone posture — the 7 SSTONK violations are structurally closed, not finding-class rated; clean closure verdict math per `D-308-INV-COUNT-01`).

### D-08 5-Bucket Severity Rubric

Severity calibration mapped via the v25-v43 player-reachability × value-extraction × determinism-break frame, carried forward as D-08 from v25 onward. Rubric is **descriptive-only at v44** since the 7 SSTONK violations are structurally closed (not finding-class rated) and zero NEW F-44-NN finding blocks landed.

| Severity | Definition |
| -------- | ---------- |
| CRITICAL | Player-reachable, material protocol value extraction, no mitigation at HEAD. |
| HIGH | Player-reachable, bounded value extraction OR no extraction but hard determinism violation. |
| MEDIUM | Player-reachable, no value extraction, observable behavioral asymmetry. |
| LOW | Player-reachable theoretically but not practically (gas economics / timing / coordination cost makes exploit non-viable). |
| INFO | Not player-reachable, OR documented design decision, OR observation only. |

### D-09 KI Gating Rubric Reference

The §6 KI-eligibility 3-predicate test (D-09) — accepted-design + non-exploitable + sticky — produces no v44 KI candidates. Phase 307 surfaced unanimous-NEGATIVE (0 FINDING_CANDIDATE across all 3 skills; 3 SAFE_BY_DESIGN documenting intentional protocol behavior; 0 skeptic-filter discards). KNOWN-ISSUES.md is UNMODIFIED at v44 close per `D-44N-KI-01`. §6 closure verdict `KNOWN_ISSUES_UNMODIFIED`.

### Forward-Cite Closure Summary

`D-44N-FCITE-01` carry of `D-303-FCITE-01` / `D-297-FCITE-01` / `D-42N-FCITE-01` / `D-281-FCITE-01` / `D-40N-FCITE-01`: zero forward-cites emitted from Phase 308 to any post-v44.0 phase numbers. Locked-decision IDs (D-43N-V44-HANDOFF-NN, D-43N-V44-ADMA-NN, D-43N-V44-ADMA-ERRATUM-01, D-44N-*, D-308-*) carry forward via descriptive labels only; v45.0+ plan-phase resolves the HANDOFF/ADMA anchors to its own phase numbering. The descriptive labels "v45.0+ FIX-MILESTONE" / "v45.0+ plan-phase" are acceptable per `D-297-FCITE-01` allowed-exception pattern carry.

### Attestation Anchor

`D-44N-CLOSURE-01` 2-commit sequential SHA orchestration: Commit 1 writes `audit/FINDINGS-v44.0.md` with `MILESTONE_V44_AT_HEAD_6f0ba2963a10654ba554a8c333c5ee80c54a8349` placeholder; Commit 2 resolves the placeholder to the Commit 1 SHA, propagates verbatim to 5 FINDINGS verbatim locations + 3 cross-document propagation targets, applies `chmod 444`, and ships the atomic 5-doc closure flip across ROADMAP + STATE + MILESTONES + PROJECT + REQUIREMENTS. Pre-authorized per `D-44N-CLOSURE-PREAUTH-01` (locked at Phase 304 SPEC signoff). §9d v45.0+ handoff register (135 anchors) is load-bearing input for the v45.0+ plan-phase.

---

## 3. Per-Phase Sections

### §3a. Phase 304 — SPEC + Invariant Model (SPEC)

**Commits.** Phase 304 spans AGENT-COMMITTED planning + SPEC commits including `6edc3967` (Plan 02 SPEC §1/§2 — INV statements + SPEC-01..05 design locks) + `315280b0` + `971688ba` (Plan 03 §3 EDGE-01..18 enumeration + day-naming consistency).

**Output.** `.planning/phases/304-spec-invariant-model-spec/304-SPEC.md` (960 lines; 35 LOCKED requirements: INV-01..12 + SPEC-01..05 + EDGE-01..18). §1 invariant model (INV-01..12 each stated as a precise formal accounting property with storage variables + state-transition window). §2 locked design decisions (SPEC-01..05: `pendingByDay[uint32]` struct shape, composite-key `pendingRedemptions[player][day]`, explicit `dayToResolve` arg on `resolveRedemptionPeriod`, gameOver-mid-pending semantics, supply-snapshot lazy-init timing). §3 EDGE-01..18 exhaustive scenario enumeration (positive + negative assertions narratively stated; §3 per-INV→EDGE coverage map). §4 design-intent backward-trace + actor game-theory walk for the 7 v44.0 deletions per `feedback_design_intent_before_deletion.md`. §5 source-verified citation manifest (61 citations grep-verified at v43.0 baseline HEAD `8111cfc5`). This is the canonical SPEC for the §3.C + §3.F invariant definitions.

### §3b. Phase 305 — Implementation (IMPL)

**Commits.** Phase 305 ships the **USER-APPROVED contract commit `213f9184 feat(305-01): v44.0 sStonk per-day redemption refactor — 1-slot DayPending + INV-13 sentinel`** (the single `contracts/` diff in the v44.0 milestone) + AGENT-COMMITTED planning bundle `c6f7045b` (Task 1 pre-patch grep-verification manifest) + `47ab0b3f` (plan-complete summary).

**Output.** `contracts/StakedDegenerusStonk.sol` refactored to per-day-keyed `pendingByDay[uint32]` storage + composite-key `pendingRedemptions[player][day]`. Emergent surfaces from execution (each USER-APPROVED inside the single batched diff): `D-305-SENTINEL-01` (`pendingResolveDay` uint32 sentinel + `PriorDayUnresolved` revert in `_submitGamblingClaimFrom` + INV-13 single-pool invariant; partially reverses SPEC §2.7 deletion 1 to fix a multi-day-RNG-stall fund-loss bug discovered during execution) + `D-305-STRUCT-TIGHTEN-01` (1-slot DayPending packing — 4×uint64 with denomination conversion) + `D-305-GWEI-SNAP-01` (ethValueOwed/burnieOwed snapped to gwei at the computation source; zero accounting drift via gcd(1e9, 100) = 100) + `D-305-DUST-FLOOR-01` (`MIN_BURN_AMOUNT = 1e18` gambling-burn floor + `BurnTooSmall` revert) + `D-305-DAYTORESOLVE-01` (AdvanceModule reads `sdgnrs.pendingResolveDay()` instead of deriving `dayToResolve = day - 1`). The diff also touched `contracts/modules/DegenerusGameAdvanceModule.sol` (3 `resolveRedemptionPeriod` call sites) + `contracts/interfaces/IStakedDegenerusStonk.sol` + `contracts/DegenerusVault.sol` (compile-cascade from the 1-arg `claimRedemption(uint32 day)`; user authorized the Vault scope expansion during execution).

### §3c. Phase 306 — Test (TST)

**Commits.** Phase 306 spans 6 AGENT-COMMITTED test commits per `D-43N-TEST-COMMITS-AUTO-01`: `de75f620` (Plan 01 invariant harness — 13 INV-NN PROVEN against v44 sStonk per-day source) + `333c803f` (Plan 02-01 EDGE-01..10) + `3143ea9c` (Plan 02-02 EDGE-11..20) + `d24a2487` (Plan 03-01 per-function fuzz — 6 ROADMAP-canonical + 2 ACL/sentinel) + `b102bc0f` (Plan 04 V-184 vm.skip flip — strict byte-identity assertion; the **only intended `test/` diff vs v43.0 baseline**; REG-01 anchor) + `e0f7d77e` (Plan 05 gas regression bench — burn ≤ +5% v43, claim ≤ +0% v43; TST-06 closure).

**Output.** `test/invariant/RedemptionAccounting.t.sol` (13 `invariant_INV_NN_*` fns; PROVEN at FOUNDRY_PROFILE=deep, 256 runs × 128 depth × 32768 calls per invariant) + `test/fuzz/RedemptionEdgeCases.t.sol` (20 `testFuzz_EDGE_NN_*` fns; PROVEN at 10k runs each; EDGE-07 V-184 byte-identity assertion at `:687`) + `test/fuzz/StakedStonkRedemption.t.sol` (8 per-fn fuzz tests: 6 ROADMAP-canonical + `testFuzz_ResolveRevertsForNonGame` + `testFuzz_BurnSetsSentinelOnFirstBurnOfDay`) + `test/fuzz/RngLockDeterminism.t.sol:1277` (V-184 strict-byte-identity assertion in `testFuzz_RngLockDeterminism_StakedStonkRedemption`; TST-05 + HANDOFF-111..117 closure; vm.skip count 17→16) + `test/fuzz/RedemptionGas.t.sol` (TST-06 gas regression: actual burn 198109 ≤ BURN_LIMIT_V44 282257 = −29.8% vs v43; actual claim 154823 ≤ CLAIM_LIMIT_V44 364565 = −57.5% vs v43). Phase 306 VERIFICATION: 13/13 must-haves verified PASS.

### §3d. Phase 307 — Cross-Surface Adversarial Sweep (SWEEP)

**Commits.** Phase 307 spans 7 AGENT-COMMITTED commits: `b3fcee2c` (CHARGE — SWP-01..05 + 5 v44-specific augments (i)..(v)) + `a83ebc4c` (`/contract-auditor` SEQUENTIAL_MAIN_CONTEXT pass — 22 NEGATIVE-VERIFIED; 0 FINDING_CANDIDATE) + `3dc7cafd` (`/zero-day-hunter` + `/economic-analyst` HYBRID-fallback pass — 22 + 28 disposition rows; 0 findings) + `5448cd5d` (integrate 3-skill MDs → ADVERSARIAL-LOG — unanimous-NEGATIVE) + `1352be27` (Phase 307 SWEEP complete — 0 elevated / Task 6 skipped) + `e58b03b9` (LOG §7 disposition row-count correction 27/27 → 72/72) + `c7ef7219` (Phase 307 VERIFICATION passed 13/13 must-haves).

**Output.** `.planning/phases/307-adversarial-sweep-sweep/307-01-ADVERSARIAL-LOG.md` (3-skill HYBRID integrated LOG + 72-row Disposition + Skeptic-Filter Discarded table + Severity-Downgrade Rationale table + two-tier consensus verdict). 72/72 disposition rows (22 auditor + 22 hunter + 28 economist); 69 NEGATIVE-VERIFIED + 3 SAFE_BY_DESIGN; 0 FINDING_CANDIDATE; 0 skeptic-filter discards. Result: **unanimous-NEGATIVE**; Task 6 elevation gate **SKIPPED** per `D-307-AUDIT-ONLY-ROUTING-01` (precondition failed — 0 surviving FINDING_CANDIDATE).

### §3e. Phase 308 — Delta Audit + Findings Consolidation (Terminal; SOURCE-TREE FROZEN)

**SOURCE-TREE FROZEN attestation.** Phase 308 contributes ZERO `contracts/` and ZERO `test/` mutations. The 13-task plan per `D-308-TASK-SPLIT-01` ships only the AGENT-COMMITTED audit deliverable + planner-private artifact bundle + 5-doc closure-flip docs. 2-commit sequential SHA orchestration per `D-44N-CLOSURE-01`: Commit 1 = audit deliverable + planner-private bundle (CONTEXT + PLAN + DRAFT + VERIFY); Commit 2 = closure flip + SHA propagation + chmod 444 + atomic 5-doc closure flip (ROADMAP + STATE + MILESTONES + PROJECT + REQUIREMENTS). Pre-authorized per `D-44N-CLOSURE-PREAUTH-01`.

**Locked decisions.** `D-308-INV-COUNT-01` (§3.F + §3.C + §9 reflect Phase 306 actual coverage 13 INV / 20 EDGE); `D-308-ADVERSARIAL-DISP-01` (§4 condensed ~17-row disposition); `D-308-DELTA-SURFACE-DEPTH-01` (§3.A 8-row load-bearing depth); `D-308-TASK-SPLIT-01` (1 plan / 13 tasks); `D-44N-CLOSURE-01` (2-commit sequential SHA orchestration); `D-44N-CLOSURE-PREAUTH-01` (autonomous Commit 2); `D-44N-KI-01` (KNOWN-ISSUES.md UNMODIFIED); `D-44N-FCITE-01` (zero forward-cite emission).

---

## §3.A Delta-Surface Table (AUDIT-01)

Row classifications per `{USER-APPROVED-contract, AGENT-COMMITTED-planning, AGENT-COMMITTED-test, AGENT-COMMITTED-audit, SOURCE_TREE_FROZEN-attestation}` token vocabulary. Delta-class token set: `{CONTRACT, TEST, PLANNING, AUDIT, ATTESTATION}`. Per `D-308-DELTA-SURFACE-DEPTH-01`, the v44.0 commit envelope is aggregated into 8 load-bearing rows (not per-commit verbatim; `git log` is the authoritative per-commit trail). Row 2 is the single USER-APPROVED `contracts/` commit, enumerated explicitly so the contract diff is unambiguous.

**Range.** `git log --no-merges 8111cfc5189f628b64b500c881f9995c3edf0ed2..HEAD --oneline -- contracts/ test/` returns exactly 1 `contracts/` commit (`213f9184`) + 6 `test/` commits (`de75f620`, `333c803f`, `3143ea9c`, `d24a2487`, `b102bc0f`, `e0f7d77e`). v44 closure HEAD `<commit-1-sha>` resolved at Commit 1.

| Row-ID | Phase | Commit-SHA-range | Subject summary | Classification | Delta-class | Cross-reference |
|--------|-------|------------------|-----------------|----------------|-------------|-----------------|
| 1 | 304 SPEC | `6edc3967` + `315280b0` + `971688ba` | v44.0 SPEC §1/§2/§3 + EDGE-01..18 enumeration + day-naming consistency | AGENT-COMMITTED-planning | PLANNING | `.planning/phases/304-*/304-SPEC.md` (960 lines; INV-01..12 + SPEC-01..05 + EDGE-01..18); §3.C + §3.F INV/EDGE definitions. |
| 2 | 305 IMPL | `213f9184` | `feat(305-01): v44.0 sStonk per-day redemption refactor — 1-slot DayPending + INV-13 sentinel`. **THE only contract diff in v44.0.** v44 closure HEAD chains to this contract diff via `MILESTONE_V44_AT_HEAD_6f0ba2963a10654ba554a8c333c5ee80c54a8349`. | USER-APPROVED-contract | CONTRACT | §3b Phase 305; §3.B sStonk-specific exempt-writer row; §3.D.2 V-184 structural closure; touches `StakedDegenerusStonk.sol` + `DegenerusGameAdvanceModule.sol` + `IStakedDegenerusStonk.sol` + `DegenerusVault.sol`. |
| 3 | 305 IMPL | `c6f7045b` + `47ab0b3f` | Phase 305 planning bundle: pre-patch grep-verification manifest + plan-complete summary | AGENT-COMMITTED-planning | PLANNING | `.planning/phases/305-*/305-01-GREP-VERIFICATION.md` + `305-01-SUMMARY.md`. |
| 4 | 306 TST | `de75f620` | `test(306-01): Foundry invariant harness — 13 INV-NN PROVEN against v44 sStonk per-day source` | AGENT-COMMITTED-test | TEST | `test/invariant/RedemptionAccounting.t.sol` (13 `invariant_INV_NN_*`); §3.C + §3.F test_id source. |
| 5 | 306 TST | `333c803f` + `3143ea9c` + `d24a2487` | EDGE-01..20 fuzz suite + 8 per-fn fuzz; 10k-runs deep PASS | AGENT-COMMITTED-test | TEST | `test/fuzz/RedemptionEdgeCases.t.sol` (20 `testFuzz_EDGE_NN_*`) + `test/fuzz/StakedStonkRedemption.t.sol` (8 per-fn). |
| 6 | 306 TST | `b102bc0f` | `test(306-04): flip V-184 / HANDOFF-111 vm.skip to strict assertion — TST-05 + REG-01 closure attestation` | AGENT-COMMITTED-test | TEST | **REG-01 anchor** — the only intended `test/` diff vs v43.0 baseline; `test/fuzz/RngLockDeterminism.t.sol:1277`; §5 REG-01; §3.D.5 HANDOFF-111..117 closure. |
| 7 | 306 TST | `e0f7d77e` | `test(306-05): gas regression bench — TST-06 closure (burn ≤ +5% v43, claim ≤ +0% v43)` | AGENT-COMMITTED-test | TEST | `test/fuzz/RedemptionGas.t.sol` (2 regression assertions PASS). |
| 8 | 307 SWEEP + 308 TERMINAL | `b3fcee2c` + `a83ebc4c` + `3dc7cafd` + `5448cd5d` + `1352be27` + `e58b03b9` + `c7ef7219` | Phase 307 3-skill HYBRID adversarial sweep — unanimous-NEGATIVE; Phase 308 TERMINAL SOURCE-TREE FROZEN attestation | AGENT-COMMITTED-audit + SOURCE_TREE_FROZEN-attestation | AUDIT + ATTESTATION | `.planning/phases/307-*/307-01-ADVERSARIAL-LOG.md` (72/72 Disposition); §4 disposition; cross-references the 2 AGENT-COMMITTED Phase 308 commits (Commit 1 deliverable + Commit 2 closure flip). |

**Aggregate.** The v44.0 milestone source-tree delta is bounded to exactly 1 USER-APPROVED `contracts/` commit (`213f9184`, row 2) + 1 intended `test/` diff (the Phase 301 vm.skip flip at `b102bc0f`, row 6; the other Phase 306 test commits add NEW test files and do not modify v43.0 audit-subject source). Phase 308 itself contributes ZERO source-tree mutations (row 8 ATTESTATION). All 19 cited SHAs exist in `git log --all --oneline`.

---

## §3.B Per-Exempt-Entry-Point Attestation Matrix (AUDIT-02)

Per AUDIT-02 + `D-308-DELIVERABLE-LAYOUT` (inherited from v43 `D-303-DELIVERABLE-LAYOUT-01`). The 3 exempt entry points are the canonical structural boundary for the rngLock freeze invariant, carried verbatim from v43.0 §3.B. The v44.0 per-day refactor inserts exactly ONE new sStonk-specific exempt writer inside the EXEMPT-ADVANCEGAME group (`redemptionPeriods[day].roll` ← `resolveRedemptionPeriod`); no other exempt class gains a new writer site. Source data: RNGLOCK-CATALOG.md §16 verdict-matrix rows tagged `EXEMPT-ADVANCEGAME` / `EXEMPT-VRFCALLBACK` / `EXEMPT-RETRYLOOTBOXRNG` + the v44 IMPL source (`contracts/StakedDegenerusStonk.sol` + `contracts/modules/DegenerusGameAdvanceModule.sol`).

### §3.B.1 — EXEMPT-ADVANCEGAME (resolution-orchestrator class)

`advanceGame()` and every function reachable from it. Per RNGLOCK-CATALOG.md §16, the EXEMPT-ADVANCEGAME tag spans every advanceGame-reachable writer for every participating slot. The v44 per-day refactor preserves this envelope and adds one new writer site.

**NEW v44 sStonk-specific row.** The exempt writer of `redemptionPeriods[uint32 day].roll` is `resolveRedemptionPeriod(uint16 roll, uint32 flipDay, uint32 dayToResolve)` at `contracts/StakedDegenerusStonk.sol:633` (writes `redemptionPeriods[dayToResolve] = RedemptionPeriod({...})` at `:654`). Attestation chain:

(a) **Reachable ONLY from `advanceGame()`.** `resolveRedemptionPeriod` is invoked from exactly 3 call sites in `contracts/modules/DegenerusGameAdvanceModule.sol` — `:1234`, `:1300`, `:1333` — all of which are inside the `advanceGame()` resolution stack (`grep -n "resolveRedemptionPeriod" contracts/modules/DegenerusGameAdvanceModule.sol` returns these 3 plus a `:1782` natspec note that backfilled gap days are NOT resolved). There is no non-advanceGame caller; `resolveRedemptionPeriod` reverts for any non-game caller (proven by `testFuzz_ResolveRevertsForNonGame` in `test/fuzz/StakedStonkRedemption.t.sol`).
(b) **Write is intrinsic to the resolution orchestrator.** The `roll` value IS the VRF-derived output of the same `advanceGame()` call's `_applyDailyRng`; writing it to `redemptionPeriods[dayToResolve].roll` is the resolution-cycle's per-day commitment.
(c) **Write-once, never mutated.** INV-01 (`invariant_INV_01_WriteOnceRoll` at `test/invariant/RedemptionAccounting.t.sol:72`) PROVEN at Phase 306: for every day D with `redemptionPeriods[D].roll != 0`, the value is written exactly once and never mutated by any subsequent state transition (`burn`, `claim`, `gameOver`, admin path). The per-day key makes the v43-era overwrite primitive structurally unreachable (see §3.D).

| Slot | Exempt writer fn (file:line) | Callsite | Attestation |
|------|------------------------------|----------|-------------|
| `redemptionPeriods[uint32 day].roll` (v44-NEW) | `resolveRedemptionPeriod` (`StakedDegenerusStonk.sol:633`; writes at `:654`) | `DegenerusGameAdvanceModule:1234`, `:1300`, `:1333` ← `advanceGame()` | EXEMPT-ADVANCEGAME — STRUCTURAL-CLOSURE (per-day keying makes the overwrite primitive unreachable; INV-01 PROVEN). Consumer-set: `claimRedemption(uint32 day)` (`StakedDegenerusStonk.sol:673`) reads `redemptionPeriods[day].roll` to compute the per-day payout. |
| S-01 `dailyIdx` | `_unlockRng` (AdvanceModule.sol:1729) | AdvanceModule resolution stack | EXEMPT-ADVANCEGAME — day-anchor written at the end of the resolution cycle (carried from v43 §3.B). |
| S-39 `rngLockedFlag` | `_finalizeRngRequest` / `_unlockRng` (AdvanceModule.sol) | AdvanceModule resolution stack | EXEMPT-ADVANCEGAME — the lock flag itself is set/cleared by the advanceGame stack as the structural boundary (carried from v43 §3.B). |
| ... (full advanceGame-reachable writer enumeration) | RNGLOCK-CATALOG.md §15/§16 per-slot writer rows | every advanceGame-reachable callsite | EXEMPT-ADVANCEGAME tag in §16 verdict-matrix row (318 tag occurrences at v43.0 baseline; unchanged at v44 except the +1 sStonk-specific row above). |

**Aggregate attestation for EXEMPT-ADVANCEGAME class.** Every slot mutation reached from the advanceGame stack is intrinsic to the resolution-orchestrator's read/write contract. The v44-NEW `redemptionPeriods[day].roll` writer (`resolveRedemptionPeriod`) is reachable only from `advanceGame()`, writes exactly once per day (INV-01 PROVEN), and is structurally bound to the per-day resolution cycle.

### §3.B.2 — EXEMPT-VRFCALLBACK (VRF-word arrival class)

`rawFulfillRandomWords()` and every function reached from it as the VRF coordinator callback. Carried verbatim from v43 §3.B — the v44.0 per-day refactor introduces no new VRF-callback writer site (the VRF callback delivers the random word; the per-day refactor consumes that word at `resolveRedemptionPeriod`, which is the EXEMPT-ADVANCEGAME orchestrator-side write, not a VRF-callback-side write).

| Slot | Writer fn (file:line) | Callsite | Attestation |
|------|-----------------------|----------|-------------|
| S-63 `rngWordByDay[day]` | `_finalizeRngRequest` daily-write (AdvanceModule.sol) | reached from `rawFulfillRandomWords` daily-arrival | EXEMPT-VRFCALLBACK — daily VRF word stored at the wall-clock day index (carried from v43 §3.B). |
| S-23 `lootboxRngWordByIndex[index]` | `_finalizeLootboxRng` (AdvanceModule.sol:1234 region) | reached from `rawFulfillRandomWords` lootbox-arrival | EXEMPT-VRFCALLBACK — VRF word arrival writes the lootbox bucket (carried from v43 §3.B). |
| ... (full VRF-callback-reachable writer enumeration) | RNGLOCK-CATALOG.md §15/§16 | every VRF-callback-reachable writer | EXEMPT-VRFCALLBACK tag in §16 verdict-matrix row (101 tag occurrences; unchanged at v44). |

**Aggregate attestation for EXEMPT-VRFCALLBACK class.** The VRF arrival path is the structural source of `randomness`; its writes are intrinsic to the entropy-delivery contract. No v44 sStonk-specific addition.

### §3.B.3 — EXEMPT-RETRYLOOTBOXRNG (failsafe class)

`retryLootboxRng()` and every function reached from it (≥6h cooldown gate + ≤1 VRF-replacement per stall event + does not manipulate any pre-lock state per `D-42N-RETRY-RNG-DOMAIN-SEP-01` Option A accepted). Carried verbatim from v43 §3.B — no v44 sStonk-specific addition.

| Slot | Writer fn (file:line) | Callsite | Attestation |
|------|-----------------------|----------|-------------|
| S-46 `lootboxRngPacked.LR_MID_DAY` (retry-side replacement) | `retryLootboxRng` body (AdvanceModule.sol) | EOA `retryLootboxRng()` after 6h cooldown | EXEMPT-RETRYLOOTBOXRNG — failsafe replaces the mid-day word in the SAME bucket the original request bound; stale callback auto-rejected by requestId match. Bit-allocation map docstring at `AdvanceModule:1157-1174` (carried from v43 §3.B). |
| S-38 `rngRequestTime` (retry-side re-arm) | `retryLootboxRng` body (AdvanceModule.sol) | EOA `retryLootboxRng()` | EXEMPT-RETRYLOOTBOXRNG — retry path re-arms the pending request timer (carried from v43 §3.B). |
| ... (full retry-reachable writer enumeration) | RNGLOCK-CATALOG.md §15/§16 | every retryLootboxRng-reachable writer | EXEMPT-RETRYLOOTBOXRNG tag in §16 verdict-matrix row (50 tag occurrences; unchanged at v44). |

**Aggregate attestation for EXEMPT-RETRYLOOTBOXRNG class.** The retry path is the documented failsafe per `D-42N-RETRY-RNG-DOMAIN-SEP-01` Option A acceptance. The `advance:1157-1174` bit-allocation map docstring is load-bearing for the per-consumer bit-slice partition. No v44 sStonk-specific addition.

### §3.B.4 — Aggregate Cross-Class Roll-Up

Across the 3 exempt entry points + 1 v44-NEW sStonk-specific row (`redemptionPeriods[day].roll` ← `resolveRedemptionPeriod` at `StakedDegenerusStonk.sol:633`), every slot mutation during the rngLock window is structurally bound to the resolution orchestrator (`advanceGame`), the VRF arrival path (`VRFCallback`), or the failsafe replacement path (`retryLootboxRng`). The v44.0 per-day refactor preserves the EXEMPT envelope without introducing any new non-exempt writer — confirmed by the Phase 307 SWEEP unanimous-NEGATIVE outcome (`307-01-ADVERSARIAL-LOG.md` 72/72 disposition rows; 0 FINDING_CANDIDATE). SWP-01.PACKING (v44 layout) + Augment (ii) (`pendingResolveDay` sentinel race/collision) + Augment (v) (Vault scope-expansion ACL) all NEGATIVE-VERIFIED.

---

## §3.C Conservation Re-Proof (AUDIT-03)

Per AUDIT-03 + `D-308-INV-COUNT-01`. Every INV-01..13 is attested as proven by a specific `invariant_INV_NN_*` fn (`test/invariant/RedemptionAccounting.t.sol`) plus cross-checking `testFuzz_EDGE_NN_*` fns (`test/fuzz/RedemptionEdgeCases.t.sol`). This section is the narrative (prose) conservation re-proof; §3.F is the structured tabular form. The same 13 INV underlie both; per-INV test_id matches across §3.C + §3.F. Per-INV entry shape: (i) INV identity + formal property; (ii) proving harness (primary `invariant_INV_NN_*` fn + file:line); (iii) cross-checking EDGE coverage; (iv) status attestation (PROVEN at FOUNDRY_PROFILE=deep — 256 runs × 128 depth × 32768 calls per invariant per `306-01-SUMMARY.md` + `306-VERIFICATION.md` ALL_PASS). The cross-checking EDGE-NN mapping follows the canonical Phase 304 SPEC §3 per-INV→EDGE coverage map.

- **INV-01 — write-once roll immutability.** For every day D with `redemptionPeriods[D].roll != 0`, the value is written exactly once and never mutated by any subsequent state transition (cite 304-SPEC §1 INV-01). Proving harness: `invariant_INV_01_WriteOnceRoll` (`test/invariant/RedemptionAccounting.t.sol:72`). Cross-checking EDGE: EDGE-07 (`testFuzz_EDGE_07_V184AttackReproductionStructuralClosure:630`, byte-identity assertion at `:687`) + EDGE-17 (`testFuzz_EDGE_17_LateDayBurnPostResolveLegitimate:1221`). Status PROVEN.
- **INV-02 — ETH conservation (dust-bounded).** Sum of per-day `ethBase` and per-claim payouts conserves the burned ETH value exactly (dust ≤ bound; cite 304-SPEC §1 INV-02). Proving harness: `invariant_INV_02_EthConservationExact` (`:103`). Cross-checking EDGE: EDGE-09 (`testFuzz_EDGE_09_NPlayersConcurrentClaimsSum:797`) + EDGE-10 (`testFuzz_EDGE_10_ReentrancyOnPayEthBlocked:858`). Status PROVEN.
- **INV-03 — BURNIE conservation (resolve-time release).** BURNIE pool conserves exactly across burn/resolve/claim (cite 304-SPEC §1 INV-03). Proving harness: `invariant_INV_03_BurnieConservationExact` (`:141`). Cross-checking EDGE: EDGE-18 (`testFuzz_EDGE_18_BurniePoolInsufficientFallback:1291`). Status PROVEN.
- **INV-04 — per-day base correctness (unresolved-day pre-condition).** `pendingByDay[D].ethBase` correctly accumulates each day's burns (cite 304-SPEC §1 INV-04). Proving harness: `invariant_INV_04_PerDayBaseCorrectness` (`:165`). Cross-checking EDGE: EDGE-03 (`testFuzz_EDGE_03_SinglePlayerMultiDayClaimsIndependent:372`) + EDGE-04 (`testFuzz_EDGE_04_MultiplePlayersSameDay:455`) + EDGE-13 (`testFuzz_EDGE_13_ZeroRoundedEthValueOwedBurnProceeds:998`) + EDGE-17 (`:1221`). Status PROVEN.
- **INV-05 — per-day cumulative correctness (mixed resolved + unresolved).** Cumulative scalar matches the sum of per-day pools across mixed resolved/unresolved state (cite 304-SPEC §1 INV-05). Proving harness: `invariant_INV_05_PerDayCumulativeCorrectness` (`:203`). Cross-checking EDGE: EDGE-01 (`testFuzz_EDGE_01_PreAdvanceGapBurnLandsInCurrentDayPool:213`) + EDGE-04 (`:455`) + EDGE-09 (`:797`). Status PROVEN.
- **INV-06 — no cross-player roll manipulation.** No non-EXEMPT actor can mutate `redemptionPeriods[D].roll` between burn and claim; attacker B's re-burn cannot mutate player A's effective roll (cite 304-SPEC §1 INV-06). Proving harness: `invariant_INV_06_NoCrossPlayerRollManipulation` (`:242`). Cross-checking EDGE: EDGE-04 (`:455`) + EDGE-07 (`:630`) + EDGE-11 (`testFuzz_EDGE_11_BurnDuringRngLockedReverts:909`). Status PROVEN.
- **INV-07 — no self-roll manipulation via timing.** Even attacker A re-burning their own claim cannot retroactively mutate the day-D roll (cite 304-SPEC §1 INV-07). Proving harness: `invariant_INV_07_NoSelfRollManipulation` (`:273`). Cross-checking EDGE: EDGE-03 (`:372`) + EDGE-05 (`testFuzz_EDGE_05_ClaimBeforeResolveReverts:515`) + EDGE-06 (`testFuzz_EDGE_06_SkippedAdvanceLongStallEventualResolution:553`) + EDGE-07 (`:630`) + EDGE-10 (`:858`). Status PROVEN.
- **INV-08 — pre-advance-gap burn safety.** A burn in the pre-advance gap lands in the correct current-day pool (cite 304-SPEC §1 INV-08). Proving harness: `invariant_INV_08_PreAdvanceGapBurnSafety` (`:302`). Cross-checking EDGE: EDGE-01 (`:213`) + EDGE-02 (`testFuzz_EDGE_02_TwoPendingDaysSimultaneous:304`) + EDGE-12 (`testFuzz_EDGE_12_BurnDuringLivenessReverts:954`) + EDGE-17 (`:1221`). Status PROVEN.
- **INV-09 — skipped-advance recovery (oldest-first ordering).** A skipped advance eventually resolves the stuck day; the single-pool sentinel collapses oldest-first ordering to the only ordering (cite 304-SPEC §1 INV-09). Proving harness: `invariant_INV_09_SkippedAdvanceRecovery` (`:328`). Cross-checking EDGE: EDGE-02 (`:304`) + EDGE-06 (`:553`) + EDGE-19 (`testFuzz_EDGE_19_MultiDayRngStallStaleClaimRecovery:1352`). Status PROVEN.
- **INV-10 — per-day supply cap (snapshot/2).** Per-day burns are capped at 50% of the lazy-init supply snapshot (cite 304-SPEC §1 INV-10). Proving harness: `invariant_INV_10_PerDaySupplyCap` (`:352`). Cross-checking EDGE: EDGE-14 (`testFuzz_EDGE_14_SupplyCapExactOneWeiOverAndLazyInit:1060`). Status PROVEN.
- **INV-11 — per-(player, day) EV cap.** Per-(player, day) EV is capped (≤ 160 ETH; cite 304-SPEC §1 INV-11). Proving harness: `invariant_INV_11_PerPlayerPerDayEvCap` (`:374`). Cross-checking EDGE: EDGE-15 (`testFuzz_EDGE_15_EvCapExactOneWeiOver:1120`) + EDGE-16 (`testFuzz_EDGE_16_CrossDayCapResetStructural:1165`). Status PROVEN.
- **INV-12 — gameOver mid-pending safety.** A pending redemption is safe across a mid-pending gameOver (cite 304-SPEC §1 INV-12). Proving harness: `invariant_INV_12_GameOverMidPending` (`:401`). Cross-checking EDGE: EDGE-08 (`testFuzz_EDGE_08_BurnGameOverClaimBothVariants:721`). Status PROVEN.
- **INV-13 — single-pool pending sentinel (v44 EMERGENT per `D-305-SENTINEL-01`).** At most one unresolved day's pool exists at any time; the `pendingResolveDay` sentinel + `PriorDayUnresolved` revert (in `_submitGamblingClaimFrom`) enforce the at-most-one-unresolved-day structural property. Proving harness: `invariant_INV_13_SinglePoolPending` (`:429`). Cross-checking coverage: the sentinel-exerciser handler action `action_burnOnPreviousDay` (`test/fuzz/handlers/RedemptionHandler.sol:443`; per `D-306-01-SENTINEL-EXERCISER-01`) reads `pendingResolveDay()` and drives the `PriorDayUnresolved` revert path for negative coverage + `testFuzz_BurnSetsSentinelOnFirstBurnOfDay` (`test/fuzz/StakedStonkRedemption.t.sol:678`) + EDGE-07 V-184 structural closure (`:630`). Status PROVEN at deep × (256 × 128 × 32768) calls per `306-VERIFICATION.md` Key-Link row (scans `daysWritten`; asserts ≤1 non-empty + sentinel; zero ghost drift).

**Aggregate roll-up.** Across the 13 formal accounting invariants, the v44.0 sStonk per-day refactor proves byte-identical conservation under all (burn, advance, claim, gameOver, transfer, approve, admin) interleavings explored by the stateful Foundry harness at FOUNDRY_PROFILE=deep (256 runs × 128 depth × 32768 calls per invariant) per `306-01-SUMMARY.md` + `306-VERIFICATION.md` ALL_PASS. INV-13 is the v44-emergent single-pool sentinel invariant from `D-305-SENTINEL-01` mechanizing the structural property that backs the V-184 closure (per-day keying makes the overwrite primitive unreachable; the `pendingResolveDay` sentinel + `PriorDayUnresolved` revert make the structural property assertable). The 20-EDGE enumeration (Phase 306 extended EDGE 18→20 with EDGE-19 multi-day-RNG-stall stale-claim recovery + EDGE-20 burn-too-small dust floor per `D-305-DUST-FLOOR-01`, `testFuzz_EDGE_20_BurnTooSmall:1416`) provides per-scenario positive + negative assertions; all 20 PROVEN at 10k runs each per `306-VERIFICATION.md` ALL_PASS. The conservation re-proof is structurally complete + mechanically attested; no waivers, no failures.

**In-band divergence attestation.** INV count diverges from ROADMAP template (12 → 13) per `D-308-INV-COUNT-01`; emergent INV-13 from `D-305-SENTINEL-01` mechanized at Phase 306 Plan 01 (`de75f620`). EDGE count diverges 18 → 20 (EDGE-19 + EDGE-20). §9 closure verdict emits 13/13 + 20/20 per Phase 306 actual coverage.

---

## §3.D V-184 Disposition — RESOLVED-AT-V44 (AUDIT-04)

Per AUDIT-04 + `D-308-DELIVERABLE-LAYOUT`. This is a v44-NEW section (no v43 P303 precedent — v43 was audit-only and DEFERRED V-184 to v44; v44 is the FIX-milestone that closes it). V-184 was the single TRUE CATASTROPHE-tier finding in the entire v43.0 catalog (HANDOFF-111 priority-1).

### §3.D.1 — V-184 pre-fix mechanic

At v43.0 baseline (`MILESTONE_V43_AT_HEAD_8111cfc5189f628b64b500c881f9995c3edf0ed2`), the original CATASTROPHE per `.planning/RNGLOCK-FIXREC.md` §103: `redemptionPeriodIndex` was a single-pool counter. An attacker burning 1 wei sDGNRS post-resolve-but-pre-next-advance could trigger a re-roll that overwrote the prior day's `roll` value, retroactively modifying every prior unclaimed player's `ethValueOwed`. Subsumption fan-out: V-184 alone closes 6 additional catalog rows (V-186 + V-188 + V-190 + V-191 + V-192 + V-193) — 7 total HANDOFF-111..117 per the FIXREC §0.6 subsumption map. Cross-reference: `.planning/RNGLOCK-FIXREC.md` §103 (V-184 mechanic + game-theory walk) + `audit/FINDINGS-v43.0.md` §9d.2 HANDOFF-111 subsumption-map row (S-56 `redemptionPeriodIndex`; CATASTROPHE — TIER-1 PRIORITY-1).

### §3.D.2 — V-184 structural closure

The v44.0 refactor (USER-APPROVED contract commit `213f9184`, attested in §3.A row 2) replaces `redemptionPeriodIndex` with per-day-keyed `pendingByDay[uint32]` storage; each day's `roll` is written to a distinct slot keyed by `dayToResolve`, so the overwrite primitive becomes structurally unreachable. There is no single `redemptionPeriodIndex` slot that can go stale; the day key flows directly from `currentDayView()` into the per-day mapping, and SPEC-04(c) `delete pendingByDay[dayToResolve]` at resolve ensures the just-resolved day's entry is zeroed before any subsequent burn could write to it (a subsequent same-wall-clock-day burn writes to a separate `pendingByDay[currentDayView()]` entry). INV-01 (`invariant_INV_01_WriteOnceRoll` at `test/invariant/RedemptionAccounting.t.sol:72`) mechanizes the structural property: for every day D with `redemptionPeriods[D].roll != 0`, the value is written exactly once and never mutated by any subsequent state transition. Cross-reference: §3.B EXEMPT-ADVANCEGAME sStonk-specific row (`redemptionPeriods[day].roll` ← `resolveRedemptionPeriod` at `StakedDegenerusStonk.sol:633`). Per 304-SPEC §4, the V-184 closure is STRUCTURAL (it derives from the storage-shape change alone; no runtime `BurnsBlockedAfterResolution` revert is added).

### §3.D.3 — V-184 INV-13 single-pool sentinel

`D-305-SENTINEL-01` emergent surface from Phase 305 IMPL: the `pendingResolveDay` (uint32) sentinel field + `PriorDayUnresolved()` revert make the single-pool structural property assertable. INV-13 (`invariant_INV_13_SinglePoolPending` at `test/invariant/RedemptionAccounting.t.sol:429`) is PROVEN at deep × (256 × 128 × 32768) calls via the sentinel-exerciser handler action `action_burnOnPreviousDay` (`test/fuzz/handlers/RedemptionHandler.sol:443`; per `D-306-01-SENTINEL-EXERCISER-01`) which deliberately drives the structurally-impossible-to-succeed window (`stamp != 0 && stamp != today`) and confirms the `PriorDayUnresolved` revert fires. The sentinel additionally closed a multi-day-RNG-stall fund-loss bug discovered during execution (the original `dayToResolve = day - 1` derivation left burn-day pools permanently stuck under multi-day stalls; the sentinel always names the at-most-one stuck day exactly).

### §3.D.4 — V-184 attack reproduction (EDGE-07 + TST-04)

`testFuzz_EDGE_07_V184AttackReproductionStructuralClosure` (`test/fuzz/RedemptionEdgeCases.t.sol:630`) is the explicit headline V-184 attack-vector reproduction per AUDIT-04 + TST-04: player A burns day D, day-D+1 advance resolves with R_{D+1}, attacker burns 1 wei post-resolve, day-D+2 advance fires; the test captures `rollPre`/`rollMid` snapshots (lines 651/669) and ASSERTs `redemptionPeriods[D].roll` is byte-identical to the first resolution at every checkpoint (`assertEq(uint256(rollPostAttack), uint256(rollPre), ...)` at `:687`; sentinel checks at `:656`/`:673`). PROVEN at 10k runs deep PASS per `306-02-SUMMARY.md` + `306-VERIFICATION.md` (Truth 6/7). Negative-coverage attestation: the attack primitive is structurally unreachable; the test exercises the would-be-attack path and confirms no state mutation.

### §3.D.5 — HANDOFF-111..117 closure attestation

Phase 306 Plan 04 (`b102bc0f test(306-04): flip V-184 / HANDOFF-111 vm.skip to strict assertion — TST-05 + REG-01 closure attestation`) flips the v43-era `vm.skip(HANDOFF-111..117)` block at `test/fuzz/RngLockDeterminism.t.sol:1277` (in `testFuzz_RngLockDeterminism_StakedStonkRedemption`) to a strict byte-identity assertion (`_assertVrfOutputByteIdentity` at `:1330`). The v43.0-skipped case PASSES at v44.0 close (`306-04-SUMMARY.md` + `306-VERIFICATION.md` Truth 10; vm.skip count 17→16 = one fewer than v43.0 baseline). The 7 catalog rows closed via the single structural fix per the FIXREC §0.6 subsumption map: HANDOFF-111 (V-184) + HANDOFF-112 (V-186) + HANDOFF-113 (V-188) + HANDOFF-114 (V-190) + HANDOFF-115 (V-191) + HANDOFF-116 (V-192) + HANDOFF-117 (V-193).

### §3.D.6 — Aggregate roll-up

V-184 RESOLVED-AT-V44 — structurally (per-day keying makes the overwrite primitive unreachable) + mechanized (INV-13 single-pool sentinel PROVEN at deep × 256×128×32768 calls; EDGE-07 attack-reproduction asserts no overwrite at `:687`; TST-05 v43-vm.skip block flipped to strict assertion with PASS at v44.0 close). HANDOFF-111..117 7-row subsumption fan-out closed via single structural refactor `213f9184` per FIXREC §0.6 subsumption map. v44.0 closure verdict §9 fragment: `7 of 7 SSTONK_VIOLATIONS RESOLVED_AT_V44`.

---

## §3.E Remaining v43 Backlog Reference (AUDIT-05)

Per AUDIT-05 + `D-308-DELIVERABLE-LAYOUT`. v44.0 does NOT consume these anchors (narrow scope — sStonk per-day refactor only); §3.E enumerates them as deferred-to-v45.0+ via reference to the v43.0 §9d handoff register. The full per-anchor enumeration is carried forward at §9d (this section is the narrative roll-up).

### §3.E.1 — Backlog scope summary

v43.0 §9d shipped a 142-anchor consolidated v44.0 FIX-MILESTONE handoff register: 119 D-43N-V44-HANDOFF-NN (FIXREC §M, HANDOFF-01..119 contiguous) + 22 D-43N-V44-ADMA-NN (ADMA §4) + 1 D-43N-V44-ADMA-ERRATUM-01. v44.0 consumed exactly 7 anchors: HANDOFF-111 (V-184) + HANDOFF-112..117 (V-186/V-188/V-190/V-191/V-192/V-193 subsumption fan-out), all closed structurally via the per-day refactor `213f9184`. Remaining: **135 anchors** deferred to v45.0+. Arithmetic: `142 - 7 = 135`. Breakdown: 112 D-43N-V44-HANDOFF-NN (HANDOFF-01..110 + HANDOFF-118..119; excludes the 7 closed by v44) + 22 D-43N-V44-ADMA-NN + 1 D-43N-V44-ADMA-ERRATUM-01 = `112 + 22 + 1 = 135` total. (Equivalently: `119 - 7 + 22 + 1 = 135`.)

### §3.E.2 — v44.0 narrow-scope justification

The v44.0 milestone scope is narrow per `D-44N-NARROW-SCOPE` (lineage from `D-43N-AUDIT-ONLY-01` — v43 deferred all 142; v44 narrows to the 7-anchor V-184 subsumption-fan-out cluster). Per REQUIREMENTS.md Out of Scope, the following are all explicitly OUT of v44 scope: all v43 FIXREC anchors outside HANDOFF-111..117 (HANDOFF-01..110 + HANDOFF-118..119) + all 22 v43 ADMA anchors + the ADMA-ERRATUM-01 catalog correction + `_payEth`/`_payBurnie` re-entrancy hardening + BURNIE/coinflip lifecycle redesign + `dailyIdx == currentDayView()` burn gate + storage migration + `claimMultipleRedemptions` batch helper + `IDegenerusGamePlayer` interface expansion beyond the minimum required by the sStonk refactor. The 135 remaining anchors are the v45.0+ workload.

### §3.E.3 — Cross-reference to §9d v45.0+ handoff register

The full per-anchor enumeration is at §9d (the structured register). §3.E is the narrative roll-up. Upstream source: `audit/FINDINGS-v43.0.md` §9d (142-anchor register); §9d (this deliverable, v44) carries the register forward minus the 7 v44-closed = 135 anchors emitted. v45.0+ plan-phase reads §9d as primary load-bearing input.

---

## §3.F Formal Invariant Attestation Matrix (AUDIT-07)

Per AUDIT-07 + `D-308-INV-COUNT-01` (override of the ROADMAP 12-row template to 13 rows reflecting Phase 306 actual coverage). This is a v44-NEW section — no prior precedent (v43 P303 was audit-only; no invariants proven, no §3.F). §3.F establishes the pattern for future FIX-milestone TERMINALs. Status enum: `{PROVEN, WAIVED-with-rationale, FAILING-blocks-closure}`. v44 outcome: all 13 PROVEN. Row order sequential INV-NN. The per-INV test_id matches §3.C verbatim.

| INV-NN | Formal Property (1-sentence) | Proving test_id (file:line) | Status |
|--------|------------------------------|------------------------------|--------|
| INV-01 | Write-once `redemptionPeriods[D].roll` immutability | `invariant_INV_01_WriteOnceRoll` (`test/invariant/RedemptionAccounting.t.sol:72`) | PROVEN |
| INV-02 | ETH conservation exact (dust-bounded) | `invariant_INV_02_EthConservationExact` (`:103`) | PROVEN |
| INV-03 | BURNIE conservation exact (resolve-time release) | `invariant_INV_03_BurnieConservationExact` (`:141`) | PROVEN |
| INV-04 | Per-day base correctness (unresolved-day pre-condition) | `invariant_INV_04_PerDayBaseCorrectness` (`:165`) | PROVEN |
| INV-05 | Per-day cumulative correctness (mixed resolved + unresolved) | `invariant_INV_05_PerDayCumulativeCorrectness` (`:203`) | PROVEN |
| INV-06 | No cross-player roll manipulation | `invariant_INV_06_NoCrossPlayerRollManipulation` (`:242`) | PROVEN |
| INV-07 | No self-roll manipulation via timing | `invariant_INV_07_NoSelfRollManipulation` (`:273`) | PROVEN |
| INV-08 | Pre-advance-gap burn safety | `invariant_INV_08_PreAdvanceGapBurnSafety` (`:302`) | PROVEN |
| INV-09 | Skipped-advance recovery (oldest-first ordering) | `invariant_INV_09_SkippedAdvanceRecovery` (`:328`) | PROVEN |
| INV-10 | Per-day supply cap (snapshot/2) | `invariant_INV_10_PerDaySupplyCap` (`:352`) | PROVEN |
| INV-11 | Per-(player, day) EV cap (≤ 160 ETH) | `invariant_INV_11_PerPlayerPerDayEvCap` (`:374`) | PROVEN |
| INV-12 | gameOver mid-pending safety | `invariant_INV_12_GameOverMidPending` (`:401`) | PROVEN |
| INV-13 | Single-pool pending sentinel (v44 EMERGENT per D-305-SENTINEL-01) | `invariant_INV_13_SinglePoolPending` (`:429`) | PROVEN |

**INV count divergence attestation.** §3.F enumerates 13 INV per `D-308-INV-COUNT-01` — diverges from the ROADMAP `AUDIT-03` / `AUDIT-07` `12 invariants` template. Emergent INV-13 from `D-305-SENTINEL-01` (single-pool sentinel + `pendingResolveDay` + `PriorDayUnresolved` revert) mechanized at Phase 306 Plan 01 (`de75f620`) PROVEN at FOUNDRY_PROFILE=deep (256 × 128 × 32768 calls). The same pattern applies to EDGE: Phase 306 extended EDGE 18→20 (EDGE-19 multi-day-RNG-stall stale-claim recovery + EDGE-20 burn-too-small dust floor per `D-305-DUST-FLOOR-01`). §9 closure verdict emits 13/13 + 20/20 per Phase 306 actual coverage, not the ROADMAP 12/18 template. (The ROADMAP/REQUIREMENTS `12 of 12` / `18 of 18` template strings are preserved in their source documents; this divergence-rationale row is the in-band record of the override.)

**Aggregate roll-up.** 13 of 13 INVARIANTS PROVEN at FOUNDRY_PROFILE=deep (256 × 128 × 32768 calls per invariant) per `306-VERIFICATION.md` ALL_PASS. 0 WAIVED. 0 FAILING. The structural property backing v44 closure (single-pool sentinel) is mechanically attested.

---

## 4. Adversarial-Pass Disposition (AUDIT-06)

Per AUDIT-06 + `D-308-ADVERSARIAL-DISP-01`. Condensed (~17 rows) — does NOT verbatim-transcribe the LOG's 72-row Disposition. Full per-row detail is at `.planning/phases/307-adversarial-sweep-sweep/307-01-ADVERSARIAL-LOG.md` (3-H2 per-skill sections + §5 integrated Disposition + §4 Skeptic-Filter Discarded + §6 Severity-Downgrade Rationale + §7 two-tier consensus verdict).

### §4.1 — Hypothesis-Disposition Table

Columns: Hypothesis-ID | Source-skill | Verdict | Severity | Consensus | LOG cross-reference. (5 SWP + 5 v44-augments + 7 beyond-charge = 17 rows.)

| Hypothesis-ID | Source-skill | Verdict | Severity | Consensus | LOG cross-reference |
|---------------|--------------|---------|----------|-----------|---------------------|
| SWP-01 (INV-01..13 + packing + interleaving) | /contract-auditor | NEGATIVE-VERIFIED | N-A | unanimous-NEGATIVE | `307-01-ADVERSARIAL-LOG.md` §1 /contract-auditor (SWP-01.INV-01..13 + SWP-01.PACKING + SWP-01.INTERLEAVING) |
| SWP-02 (novel surfaces; lootbox/coinflip composition; ERC20-callback re-entry; cross-module races) | /zero-day-hunter | NEGATIVE-VERIFIED | N-A | unanimous-NEGATIVE | `307-01-ADVERSARIAL-LOG.md` §2 /zero-day-hunter (SWP-02.A..P; sDGNRS non-transferable + CEI ordering + EIP-6780) |
| SWP-03 (game-theoretic write effects; coordinated-burn; timing arbitrage; MEV) | /economic-analyst | NEGATIVE-VERIFIED | N-A | unanimous-NEGATIVE | `307-01-ADVERSARIAL-LOG.md` §3 /economic-analyst (SWP-03.1..16; pro-rata invariance proved) |
| SWP-04 (two-tier consensus per D-307-CONSENSUS-01) | (orchestrator) | NEGATIVE-VERIFIED | N-A | Tier-1 NOT triggered; Tier-2 NOT triggered; auto-RE-PASS NOT triggered | `307-01-ADVERSARIAL-LOG.md` §7 two-tier consensus verdict |
| SWP-05 (per-skill disposition + dual-gate skeptic filter per D-307-SKEPTIC-FILTER-01) | (orchestrator) | NEGATIVE-VERIFIED | N-A | unanimous-NEGATIVE; 0 discards | `307-01-ADVERSARIAL-LOG.md` §4 Skeptic-Filter Discarded (empty) |
| Augment (i) — 1-slot DayPending packing surface | /contract-auditor + /zero-day-hunter + /economic-analyst | NEGATIVE-VERIFIED | N-A | unanimous-NEGATIVE | `307-01-ADVERSARIAL-LOG.md` Augment (i) across all 3 skills |
| Augment (ii) — `pendingResolveDay` sentinel reachability + `PriorDayUnresolved` revert window | /contract-auditor + /zero-day-hunter + /economic-analyst | NEGATIVE-VERIFIED | N-A | unanimous-NEGATIVE | `307-01-ADVERSARIAL-LOG.md` Augment (ii) across all 3 skills |
| Augment (iii) — gwei-snap precision per D-305-GWEI-SNAP-01 | /contract-auditor + /zero-day-hunter + /economic-analyst | NEGATIVE-VERIFIED | N-A | unanimous-NEGATIVE | `307-01-ADVERSARIAL-LOG.md` Augment (iii) (gwei-snap × cap arithmetic; floor-div edges) |
| Augment (iv) — Phase 306 INV harness gap (sentinel-exerciser fidelity per D-306-01-SENTINEL-EXERCISER-01) | /contract-auditor + /zero-day-hunter + /economic-analyst | NEGATIVE-VERIFIED | N-A | unanimous-NEGATIVE | `307-01-ADVERSARIAL-LOG.md` Augment (iv) (8-sub-class harness-gap arm; all NEGATIVE-VERIFIED) |
| Augment (v) — Vault scope-expansion ACL surface | /contract-auditor + /zero-day-hunter + /economic-analyst | NEGATIVE-VERIFIED | N-A | unanimous-NEGATIVE | `307-01-ADVERSARIAL-LOG.md` Augment (v) (Vault composability + re-entry) |
| BC: MEV burn-ordering in same block | /economic-analyst | NEGATIVE-VERIFIED | N-A | unanimous-NEGATIVE (pro-rata invariance) | `307-01-ADVERSARIAL-LOG.md` §3 SWP-03.4 |
| BC: Vault flash-loan-DGVE attack | /economic-analyst | NEGATIVE-VERIFIED | N-A | STRUCTURALLY UNREACHABLE (burn-to-claim spans 2+ days) | `307-01-ADVERSARIAL-LOG.md` §3 SWP-03.10 |
| BC: Sybil pool-inflation across rngLock window | /economic-analyst | NEGATIVE-VERIFIED | N-A | unanimous-NEGATIVE | `307-01-ADVERSARIAL-LOG.md` §3 BC.3 |
| BC: Late-entrant pro-rata fairness / timing arbitrage | /economic-analyst | NEGATIVE-VERIFIED | N-A | unanimous-NEGATIVE | `307-01-ADVERSARIAL-LOG.md` §3 BC.2 |
| BC: Whale-coordination quick-drain across days | /economic-analyst | NEGATIVE-VERIFIED | N-A | unanimous-NEGATIVE (50% per-day cap structural) | `307-01-ADVERSARIAL-LOG.md` §3 BC.4 + BC.1 SAFE_BY_DESIGN (coordinated activity-score = INTENDED engagement) |
| BC: Activity-score griefing | /economic-analyst | NEGATIVE-VERIFIED | N-A | unanimous-NEGATIVE (per-player metric, not depletable) | `307-01-ADVERSARIAL-LOG.md` §3 BC.5 |
| BC: Coordinated mass-claim coinflip-drain MEV | /economic-analyst | NEGATIVE-VERIFIED | N-A | unanimous-NEGATIVE (coinflip credits per-player) | `307-01-ADVERSARIAL-LOG.md` §3 BC.6 |

**SAFE_BY_DESIGN rows (informational; NOT FINDING_CANDIDATE).** 3 economist rows document intentional protocol behavior auditable for the trail: SWP-03.8 (activity-score snapshot timing — INTENDED protocol mechanic per SKILL.md) + SWP-03.13 (partial-claim BURNIE STUCK on gameOver pre-flipDay — v43-baseline behavior preserved into v44 unchanged; LOW informational) + BC.1 (coordinated whales bid-up activity-score — INTENDED engagement incentive).

### §4.2 — Adversarial-Pass Outcome Summary

Source: `.planning/phases/307-adversarial-sweep-sweep/307-01-ADVERSARIAL-LOG.md`.

Phase 307 ran a 3-skill HYBRID adversarial pass (`/contract-auditor` SEQUENTIAL_MAIN_CONTEXT + `/zero-day-hunter` + `/economic-analyst` HYBRID-fallback to SEQUENTIAL_MAIN_CONTEXT — Task tool not available in executor's tool set, per v43 P302 + v42 P296 precedent; persona fidelity preserved via dedicated per-skill MDs) per `D-307-INVOKE-01` / `D-307-DISPATCH-01`. Charge per `D-307-CHARGE-01`: SWP-01..05 + 5 v44-specific augments (i)..(v) + `/economic-analyst` beyond-charge surfaces. Result: **unanimous-NEGATIVE outcome** — **72/72 disposition rows** (22 auditor + 22 hunter + 28 economist); 69 NEGATIVE-VERIFIED + 3 SAFE_BY_DESIGN; **0 FINDING_CANDIDATE**; **Task 6 elevation gate SKIPPED** per `D-307-AUDIT-ONLY-ROUTING-01` / `D-307-ELEVATION-ROUTING-01` conditional gating (precondition failed — 0 surviving FINDING_CANDIDATE). Two-tier consensus per `D-307-CONSENSUS-01`: Tier-1 not triggered (count 0); Tier-2 not triggered (count 0). Skeptic-reviewer filter per `feedback_skeptic_pass_before_catastrophe.md` + `D-307-SKEPTIC-FILTER-01` dual-gate applied; 0 discards. `/degen-skeptic` OUT OF SCOPE per `D-271-ADVERSARIAL-02` carry. `/economic-analyst` IN SCOPE per `D-271-ADVERSARIAL-03` carry. Invocation pre-authorized per `D-44N-SWEEP-PREAUTH-01`.

### §4.3 — Beyond-charge surface enumeration

The `/economic-analyst` beyond-charge surfaces (cross-referenced to LOG §3 BC.1..BC.6 + the MEV burn-ordering SWP-03.4 row): MEV burn-ordering + vault flash-loan + Sybil pool-inflation + late-entrant pro-rata fairness + whale-coordination quick-drain + activity-score griefing + coordinated mass-claim coinflip-drain. Verdict breakdown across the beyond-charge set: NEGATIVE-VERIFIED for the exploit-shaped surfaces (flash-loan structurally unreachable; whale-drain bounded by the 50% per-day cap; coinflip credits per-player; sybil/late-entrant pro-rata fairness preserved) + SAFE_BY_DESIGN for the coordinated activity-score engagement surface (BC.1 — INTENDED). Zero elevations.

### §4.4 — Skeptic-Reviewer Filter Attestation

Per `feedback_skeptic_pass_before_catastrophe.md` + `D-307-SKEPTIC-FILTER-01` dual-gate filter (per-skill self-filter + orchestrator integration-time re-application). Per-skill self-discards: `/contract-auditor` 0, `/zero-day-hunter` 0, `/economic-analyst` 0. Orchestrator integration-time additional discards: 0 (union of all 3 skills' FINDING_CANDIDATE sets = empty, so neither the (a)-only hard-discard arm nor the (b)+(c) severity-downgrade arm had inputs). Net per LOG §6 Severity-Downgrade Rationale: 0 severity downgrades (the SWP-03.13 `LOW (informational)` tag is the original SAFE_BY_DESIGN disposition's severity tag, not a downgrade). **Total filter-discarded: 0.** This deliverable summarizes the LOG outcome; it does NOT re-run the skeptic filter (per `feedback_skeptic_pass_before_catastrophe.md` — Phase 307 already operationalized it; §4 cross-references the LOG for per-row provenance).

---

## 5. LEAN Regression Appendix (REG-01)

Per REG-01. v44 ships a single REG row because closure scope is narrow: a single contract diff (`213f9184`) + a single intended test diff (`b102bc0f` — the Phase 301 vm.skip flip).

### §5a. REG-01 — v43.0 Closure-Signal Non-Widening

**REG-01 PASS.** v43.0 closure signal `MILESTONE_V43_AT_HEAD_8111cfc5189f628b64b500c881f9995c3edf0ed2` NON-WIDENING at v44.0 close HEAD. Every v43.0 audit-subject surface (Phase 298 CATALOG + Phase 299 FIXREC + Phase 300 ADMA + Phase 301 FUZZ + Phase 302 SWEEP outputs) is byte-identical at v44.0 close EXCEPT the Phase 301 `vm.skip(HANDOFF-111..117)` block flipped to a strict byte-identity assertion at `test/fuzz/RngLockDeterminism.t.sol:1277` (intended diff attested in §3.A row 6; Phase 306 Plan 04 commit `b102bc0f`). The v44 contract diff (`213f9184`) is scoped to the per-day refactor of `contracts/StakedDegenerusStonk.sol` + `contracts/modules/DegenerusGameAdvanceModule.sol` call-site updates at `:1234`/`:1300`/`:1333` + `contracts/interfaces/IStakedDegenerusStonk.sol` + `contracts/DegenerusVault.sol` (compile-cascade) per SPEC. The v43 audit-subject surfaces NOT in v44 scope (the rngLock freeze invariant across the 13-consumer set; FIXREC §M HANDOFF-01..110 + HANDOFF-118..119 non-V-184 entries; ADMA §3 R-01..R-22; FUZZ harness fns other than the V-184 vm.skip line) remain byte-identical from v43.0 close.

**Evidence (grep gates run at T11 verification):**

- `git diff 8111cfc5189f628b64b500c881f9995c3edf0ed2..HEAD -- contracts/StakedDegenerusStonk.sol contracts/modules/DegenerusGameAdvanceModule.sol --stat` — diff bounded to the v44-in-scope per-day refactor changes (the USER-APPROVED `213f9184` diff).
- `git diff 8111cfc5189f628b64b500c881f9995c3edf0ed2..HEAD -- test/fuzz/RngLockDeterminism.t.sol --stat` — diff bounded to the V-184 vm.skip line flipped to a strict assertion (vm.skip count 17→16).
- `git diff 8111cfc5189f628b64b500c881f9995c3edf0ed2..HEAD -- .planning/RNGLOCK-CATALOG.md .planning/RNGLOCK-FIXREC.md .planning/ADMIN-AUDIT.md` — expected: no output (v43 audit artifacts UNMODIFIED at v44 close).
- `git diff 8111cfc5189f628b64b500c881f9995c3edf0ed2..HEAD -- KNOWN-ISSUES.md` — expected: no output per `D-44N-KI-01`.

### §5b. Regression Distribution Summary

**REG-01 PASS / 0 REGRESSED at v44.0 close.** The Phase 301 vm.skip flip at `test/fuzz/RngLockDeterminism.t.sol:1277` is the ONLY intended `test/` diff vs the v43.0 baseline; it lands at Phase 306 Plan 04 `b102bc0f` and is attested in §3.A row 6 + §3.D.5. The USER-APPROVED contract diff (`213f9184`) is the ONLY intended `contracts/` diff vs the v43.0 baseline; it is attested in §3.A row 2 + §3b + §3.D.2. All other v43.0 audit-subject surfaces are byte-identical. (The other Phase 306 test commits add NEW test files — `RedemptionAccounting.t.sol`, `RedemptionEdgeCases.t.sol`, `StakedStonkRedemption.t.sol` — and extend `RedemptionGas.t.sol`; they do not modify any v43.0 audit-subject source surface.)

---

## 6. KI Gating Walk + KNOWN-ISSUES.md Re-Verification (AUDIT-08)

Per AUDIT-08 + `D-44N-KI-01`. 4 prose paragraphs (one per KI envelope) + 1 closure verdict line. KNOWN-ISSUES.md is UNMODIFIED across both Phase 308 commits.

### 6.1. EXC-01 RE_VERIFIED-NEGATIVE-scope at v44

EXC-01 (Non-VRF entropy for affiliate winner roll; KNOWN-ISSUES.md line 17) RE_VERIFIED-NEGATIVE-scope at v44 close per `D-44N-KI-01`. The v44 audit subject is the sStonk per-day redemption refactor; it touches only `contracts/StakedDegenerusStonk.sol` + `contracts/modules/DegenerusGameAdvanceModule.sol` (`resolveRedemptionPeriod` call sites) + `contracts/interfaces/IStakedDegenerusStonk.sol` + `contracts/DegenerusVault.sol` — structurally separate from the EXC-01 affiliate-roll surface (the affiliate winner roll's deterministic seed is untouched by the per-day refactor). Zero affiliate-roll interaction in v44 scope.

### 6.2. EXC-02 RE_VERIFIED-NEGATIVE-scope at v44

EXC-02 (Gameover prevrandao fallback in `_getHistoricalRngFallback`; KNOWN-ISSUES.md line 29) RE_VERIFIED-NEGATIVE-scope at v44 close. The v44 audit scope has zero AdvanceModule game-over-RNG-substitution interaction beyond sStonk-internal; the `resolveRedemptionPeriod` call sites at `DegenerusGameAdvanceModule:1234`/`:1300`/`:1333` remain inside the EXEMPT-ADVANCEGAME envelope per §3.B and do not alter the `_gameOverEntropy` / `_getHistoricalRngFallback` 14-day-delay fallback path.

### 6.3. EXC-03 RE_VERIFIED-NEGATIVE-scope at v44

EXC-03 (Gameover RNG substitution for mid-cycle write-buffer tickets; KNOWN-ISSUES.md line 36) RE_VERIFIED-NEGATIVE-scope at v44 close. Same NEGATIVE-scope justification as §6.2 — the per-day refactor's resolve call sites stay inside the EXEMPT-ADVANCEGAME envelope; the gameover write-buffer substitution surface is structurally separate from the sStonk per-day pool. INV-12 (`invariant_INV_12_GameOverMidPending`) PROVEN at Phase 306 confirms the sStonk per-day pool is safe across a mid-pending gameOver, with no interaction with the EXC-03 write-buffer substitution mechanic.

### 6.4. EXC-04 STRUCTURALLY ELIMINATED preserved

**EXC-04 (EntropyLib XOR-shift PRNG STRUCTURALLY ELIMINATED at v40 P278).** Grep proof at v44 close HEAD:

```
$ grep -rn "entropyStep" contracts/
(zero matches)
```

`EntropyLib.entropyStep` was deleted at v40 Phase 278 `8a81a87c` and has NOT been reintroduced through v41 + v42 + v43 + v44. The v44 source-tree-freeze attestation at §3.A row 8 confirms Phase 308 contributes zero `contracts/` mutations; the only `contracts/` diff in the v44 milestone is `213f9184`, which modifies the sStonk per-day surfaces with zero `EntropyLib` touch. EXC-04 STRUCTURALLY ELIMINATED disposition preserved at v44 close.

### 6.5. Closure verdict

**`KNOWN_ISSUES_UNMODIFIED`** per `D-44N-KI-01` default. v44 surfaced zero F-44-NN-eligible candidates (FIX-milestone posture: the 7 SSTONK violations are structurally closed via the per-day refactor, not finding-class promoted). Phase 307 unanimous-NEGATIVE (0 FINDING_CANDIDATE; Task 6 elevation gate SKIPPED). KNOWN-ISSUES.md byte-identical across both Phase 308 commits — verified at §9 closure attestation via `git diff HEAD~2 HEAD -- KNOWN-ISSUES.md` returning no output.

---

## 7. Prior-Artifact Cross-Cites

Per AUDIT-09. Per-milestone + per-phase cross-cite matrix with disposition at v44.0 close HEAD. Disposition enum: `{RESOLVED, NEGATIVE-scope, SUPERSEDED}`. Carry-forward decision-anchor enumeration (≥ 50 D-NN-* IDs) at §7.5.

### 7.1. v44.0 Phase Artifacts

**Phase 304 SPEC + Invariant Model:**
- `.planning/phases/304-spec-invariant-model-spec/304-CONTEXT.md`
- `.planning/phases/304-spec-invariant-model-spec/304-01..03-PLAN.md`
- `.planning/phases/304-spec-invariant-model-spec/304-SPEC.md` (canonical Phase 304 deliverable; INV-01..12 + SPEC-01..05 + EDGE-01..18 enumeration)

**Phase 305 IMPL (the v44.0 sStonk per-day redemption refactor):**
- `.planning/phases/305-implementation-impl/305-CONTEXT.md`
- `.planning/phases/305-implementation-impl/305-01-PLAN.md`
- `.planning/phases/305-implementation-impl/305-01-GREP-VERIFICATION.md` (pre-patch grep-verification manifest per `feedback_verify_call_graph_against_source.md`)
- `.planning/phases/305-implementation-impl/305-01-SUMMARY.md`
- `213f9184 feat(305-01): v44.0 sStonk per-day redemption refactor — 1-slot DayPending + INV-13 sentinel` (the single USER-APPROVED `contracts/` commit; §3.A row 2)

**Phase 306 TST (Foundry invariant + fuzz coverage):**
- `.planning/phases/306-test-tst/306-CONTEXT.md`
- `.planning/phases/306-test-tst/306-01..05-PLAN.md`
- `.planning/phases/306-test-tst/306-VERIFICATION.md` (ALL_PASS aggregate; 13 INV + 20 EDGE deep-profile coverage)
- `test/invariant/RedemptionAccounting.t.sol` + `test/fuzz/RedemptionEdgeCases.t.sol` + `test/fuzz/StakedStonkRedemption.t.sol` + `test/fuzz/RedemptionGas.t.sol` (canonical Phase 306 deliverables; AGENT-COMMITTED per `D-43N-TEST-COMMITS-AUTO-01` carry)
- `test/fuzz/RngLockDeterminism.t.sol` (vm.skip flip at `:1277` — the only intended `test/` diff vs v43.0 baseline; `b102bc0f`)

**Phase 307 SWEEP (3-skill HYBRID adversarial pass):**
- `.planning/phases/307-adversarial-sweep-sweep/307-CONTEXT.md`
- `.planning/phases/307-adversarial-sweep-sweep/307-01-PLAN.md`
- `.planning/phases/307-adversarial-sweep-sweep/307-01-ADVERSARIAL-LOG.md` (canonical integrated 3-H2 + 72-row Disposition LOG)

**Phase 308 TERMINAL (this milestone):**
- `.planning/phases/308-delta-audit-findings-consolidation-terminal/308-CONTEXT.md`
- `.planning/phases/308-delta-audit-findings-consolidation-terminal/308-01-PLAN.md`
- `.planning/phases/308-delta-audit-findings-consolidation-terminal/308-FINDINGS-DRAFT.md`
- `.planning/phases/308-delta-audit-findings-consolidation-terminal/308-FINDINGS-VERIFY.md`

### 7.2. Prior Milestone FINDINGS Cross-Cites

Per-finding spot-check matrix across the v25.0 → v43.0 deliverable chain. Disposition at v44.0 close HEAD:

| Prior deliverable | Headline finding(s) | Disposition at v44.0 close |
|-------------------|---------------------|----------------------------|
| `audit/FINDINGS-v43.0.md` | V-184 sStonk cross-day re-roll CATASTROPHE (HANDOFF-111); audit-only DEFER of 142-anchor register | **RESOLVED** — V-184 + HANDOFF-112..117 fan-out structurally closed at v44 (`213f9184`); 135 of 142 anchors carry forward to v45.0+ (§9d) |
| `audit/FINDINGS-v42.0.md` | ZERO F-42-NN; 1 Tier-1 ACCEPT_AS_DOCUMENTED on (xiv) retryLootboxRng entropy-correlation; KI UNMODIFIED | **NEGATIVE-scope** — (xiv) carried forward as `D-42N-RETRY-RNG-DOMAIN-SEP-01` (§9d.6); no v44 interaction |
| `audit/FINDINGS-v41.0.md` | 3 F-41-NN finding blocks RESOLVED_AT_V41 (F-41-01 owed-salt; F-41-02/03 dailyIdx) | **RESOLVED** — FIX-milestone verdict-math precedent (`3 of 3 F-41-NN RESOLVED_AT_V41`) inherited by v44 `7 of 7 SSTONK_VIOLATIONS RESOLVED_AT_V44` |
| `audit/FINDINGS-v40.0.md` | ZERO F-40-NN; KI MODIFIED at close — EXC-04 EntropyLib removed outright at v40 P278 (`8a81a87c`) | **NEGATIVE-scope** — EXC-04 STRUCTURALLY ELIMINATED preserved (§6.4 grep proof ZERO matches) |
| `audit/FINDINGS-v39.0.md` | 5 FINDINGS-verbatim-location convention reference | **SUPERSEDED** — convention carried into v44 §9c |
| `audit/FINDINGS-v38.0.md` .. `audit/FINDINGS-v35.0.md` | mid-milestone references; zero F-NN findings each | **NEGATIVE-scope** — no v44 audit-subject overlap |
| `audit/FINDINGS-v34.0.md` | TraitUtils + `_pickSoloQuadrant` + JackpotBucketLib byte-identity baseline (REG-03 inheritance) | **NEGATIVE-scope** — outside v44 sStonk-per-day audit subject |
| `audit/FINDINGS-v33.0.md` .. `audit/FINDINGS-v25.0.md` | full prior-milestone deliverable chain; D-08 + D-09 rubric origin | **SUPERSEDED** — D-08 5-Bucket Severity + D-09 KI Gating rubrics carried forward to v44 §2 |

### 7.3. Notes Cross-Cites

- `KNOWN-ISSUES.md` (UNMODIFIED at v44 close per `D-44N-KI-01`; EXC-01..03 active entries at lines 17 / 29 / 36 + EXC-04 structural-elimination disposition documented in prose — §6 walkthrough enumerates each NEGATIVE-scope justification). **Disposition: NEGATIVE-scope (byte-identical across both Phase 308 commits).**
- `.planning/RNGLOCK-FIXREC.md` §103 (V-184 mechanic + game-theory walk) + §0.6 subsumption map (HANDOFF-111 7-row fan-out). **Disposition: RESOLVED at v44 (cited verbatim in §3.D.1 + §3.D.5; UNMODIFIED at v44 close).**
- `.planning/RNGLOCK-CATALOG.md` §15/§16 verdict matrix (S-56 `redemptionPeriodIndex` row; per-class EXEMPT tag counts). **Disposition: NEGATIVE-scope (v43 audit artifact UNMODIFIED at v44 close per §5 REG-01 grep gate).**
- `.planning/ADMIN-AUDIT.md` §4 (22 ADMA anchors). **Disposition: NEGATIVE-scope (UNMODIFIED at v44 close; carried forward at §9d.4).**
- `.planning/MILESTONES.md` (v43.0 archive entry; immediate prior reference for v44.0 archive shape at Commit 2).

### 7.4. Project-State Cross-Cites

- `.planning/ROADMAP.md` (Phase 308 entry; 5 success criteria; AUDIT-01..09 + REG-01 + CLS-01..02 references; depends on Phases 304-307; SOURCE-TREE FROZEN attestation; 9-section deliverable shape).
- `.planning/REQUIREMENTS.md` (63 milestone-total requirement IDs: 13 INV + 5 SPEC + 4 IMPL + 7 TST + 20 EDGE + 5 SWP + 9 AUDIT + 1 REG + 2 CLS; AUDIT/REG/CLS pending-status table at v44 close, flipped to Complete at Commit 2).
- `.planning/STATE.md` (Phase 307 Complete marker; ready to plan Phase 308 → executing → complete; v43.0 last-shipped block carries forward → v44.0 rotates to Last Shipped at Commit 2).
- `.planning/PROJECT.md` (v44.0 milestone scope + v43.0 audit baseline `MILESTONE_V43_AT_HEAD_8111cfc5189f628b64b500c881f9995c3edf0ed2`).

### 7.5. Carry-Forward Decision Anchors (Full Chain)

- **v25.0 chain:** `D-08` (5-Bucket Severity Rubric); `D-09` (KI Gating Rubric).
- **v32.0+ FCITE chain:** `D-NN-FCITE-01` → `D-40N-FCITE-01` → `D-281-FCITE-01` → `D-42N-FCITE-01` → `D-297-FCITE-01` → `D-303-FCITE-01` → `D-44N-FCITE-01` (terminal-phase zero forward-cite emission).
- **v37.0 chain:** `D-271-ADVERSARIAL-01` + `D-271-ADVERSARIAL-02` (`/degen-skeptic` OUT OF SCOPE) + `D-271-ADVERSARIAL-03` (`/economic-analyst` IN SCOPE).
- **v40.0 chain:** `D-40N-MINTBOOST-OUT-01`; `D-40N-LBX02-OUT-01`; `D-40N-EVT-BREAK-01`; `D-40N-CLOSURE-01`.
- **v41.0 chain:** `D-281-FIX-SHAPE-01`; `D-288-FIX-SHAPE-01`; `D-284-CLOSURE-01`; `D-284-ADVERSARIAL-RE-PASS-01`; `D-281-KI-01`.
- **v42.0 chain:** `D-42N-EVT-BREAK-01`; `D-42N-MINTCLN-SCOPE-01`; `D-42N-DETERMINISM-01`; `D-42N-GAS-01`; `D-294-CALLER-UNIFORM-01`; `D-42N-CLOSURE-01`; `D-42N-FCITE-01`; `D-42N-RETRY-RNG-DOMAIN-SEP-01`; `D-42N-RETRY-RNG-SCOPE-DOC-01`; `D-42N-RETRY-RNG-LAUNCH-FAQ-01`.
- **v42.0 Phase 296/297 chain:** `D-296-CHARGE-01`; `D-296-CONSENSUS-01`; `D-296-INVOKE-01`; `D-297-CLOSURE-01`; `D-297-VERDICT-01`; `D-297-DEFER-01`; `D-297-FINDINGS-FRONTMATTER-01`.
- **v43.0 chain:** `D-43N-AUDIT-ONLY-01`; `D-43N-CLOSURE-PREAUTH-01`; `D-43N-TEST-COMMITS-AUTO-01`; `D-43N-SWEEP-PREAUTH-01`; `D-43N-FUZZ-VMSKIP-01`; `D-43N-KI-01`; `D-298-OZ-CARVEOUT-01`; `D-299-FIXREC-LAYOUT-01`; `D-300-ADMA-LAYOUT-01`; `D-301-VMSKIP-MECHANISM-01`; `D-301-EDGE-CASES-01`; `D-302-CHARGE-01`; `D-302-CONSENSUS-01`; `D-302-AUDIT-ONLY-ROUTING-01`; `D-303-DELIVERABLE-LAYOUT-01`; `D-303-VERDICT-01`; `D-303-CLOSURE-01`; `D-303-KI-01`; `D-303-V44-HANDOFF-REGISTER-01`; `D-303-FCITE-01`; `D-303-EXEC-SHAPE-01`; `D-303-RESEARCH-AGENT-01`; `D-303-TASK-SPLIT-01`.
- **v44.0 chain (this milestone):** `D-44N-CLOSURE-01` + `D-44N-CLOSURE-PREAUTH-01` + `D-44N-KI-01` + `D-44N-FCITE-01` + `D-44N-SWEEP-PREAUTH-01` + `D-44N-NARROW-SCOPE` + `D-304-SPEC-LAYOUT-01` + `D-305-SENTINEL-01` + `D-305-STRUCT-TIGHTEN-01` + `D-305-GWEI-SNAP-01` + `D-305-DUST-FLOOR-01` + `D-305-DAYTORESOLVE-01` + `D-306-01-SENTINEL-EXERCISER-01` + `D-307-CHARGE-01` + `D-307-CONSENSUS-01` + `D-307-INVOKE-01` + `D-307-SKEPTIC-FILTER-01` + `D-307-AUDIT-ONLY-ROUTING-01` + `D-308-INV-COUNT-01` + `D-308-ADVERSARIAL-DISP-01` + `D-308-DELTA-SURFACE-DEPTH-01` + `D-308-TASK-SPLIT-01`.

---

## 8. Forward-Cite Closure

Per AUDIT-09 + `D-44N-FCITE-01` (carry of `D-303-FCITE-01` / `D-297-FCITE-01` / `D-42N-FCITE-01` / `D-281-FCITE-01` / `D-40N-FCITE-01`). Zero forward-cites emitted from Phase 308 to any post-v44.0 milestone phase numbers across scoped artifacts.

### 8a. Phase 308 Intra-Milestone Forward-Cite Residual Verification

**Scoped artifacts:** `audit/FINDINGS-v44.0.md` (this deliverable, promoted at Commit 1) + `.planning/phases/308-delta-audit-findings-consolidation-terminal/308-FINDINGS-DRAFT.md` (planner-private byte-identical mirror).

**Grep-command attestation (run at T11 verification Sub-check 10 + reconfirmed at T12 acceptance):**

```
$ grep -nE 'v45\.0[+]|Phase 30[9]|Phase 3[1-9][0-9]' audit/FINDINGS-v44.0.md \
    | grep -v 'v45\.0+ FIX-MILESTONE' \
    | grep -v 'v45\.0+ plan-phase' \
    | grep -v 'D-43N-V44-\(HANDOFF\|ADMA\)' \
    | grep -v 'D-43N-V44-ADMA-ERRATUM-01'
(zero matches)
```

ZERO matches for any post-Phase-308 phase-number token (any phase number strictly greater than 308 across the `30[9]` / `31[0-9]` / `3[2-9][0-9]` grep-pattern ranges) across the scoped artifacts after the allowed-exception filter.

**Allowed exceptions per `D-44N-FCITE-01`:** Locked-decision IDs (D-44N-* + D-308-* + D-43N-V44-HANDOFF-NN + D-43N-V44-ADMA-NN + D-43N-V44-ADMA-ERRATUM-01) carry forward via descriptive labels only. None of these IDs match the post-milestone forward-cite grep patterns. Descriptive labels "v45.0+ FIX-MILESTONE" / "v45.0+ plan-phase" are acceptable per `D-297-FCITE-01` allowed-exception pattern carry — they refer to the milestone version, not a phase number; the v45.0+ plan-phase resolves the HANDOFF/ADMA anchors to its own phase numbering.

### 8b. Phase 308 → Post-Milestone Forward-Cite Emission

Zero post-milestone phase-number references emitted. The §9d v45.0+ handoff register uses locked-decision IDs + descriptive labels only (e.g., "v45.0+ FIX-MILESTONE consolidated handoff register"; "domain-separation policy revisit deferred"; "indexer-migration handoff"; "launch-comms FAQ"). No phase numbers, no version numbers beyond the v44.0 closure + the v45.0+ descriptive-label allowed exception.

### 8c. Combined §8 Verdict

**FORWARD_CITE_ZERO_PASS.** Phase 308 emits zero post-Phase-308 forward-cites across scoped artifacts. The §9d register routes future work through locked-decision IDs + descriptive labels per `D-44N-FCITE-01` discipline. The v45.0+ plan-phase consumes the 135-anchor handoff register from §9d as load-bearing input and resolves the HANDOFF/ADMA anchors to its own phase numbering.

---

## 9. Milestone Closure Attestation (AUDIT-09)

Per AUDIT-09 + `D-308-INV-COUNT-01` + `D-44N-CLOSURE-01` + `D-44N-CLOSURE-PREAUTH-01`.

### 9a. Closure Verdict

**`7 of 7 SSTONK_VIOLATIONS RESOLVED_AT_V44; 13 of 13 INVARIANTS PROVEN; 20 of 20 EDGE_CASES TESTED; 0 NEW_FINDINGS; KNOWN_ISSUES_UNMODIFIED`** per `D-308-INV-COUNT-01` strict math (override of the ROADMAP `12 of 12 / 18 of 18` template).

- **SSTONK_VIOLATIONS resolved:** 7 of 7 (V-184 + V-186 + V-188 + V-190 + V-191 + V-192 + V-193 = HANDOFF-111..117; closed via the single structural refactor `213f9184` per the FIXREC §0.6 subsumption map — §3.D).
- **INVARIANTS proven:** 13 of 13 (INV-01..13 PROVEN at FOUNDRY_PROFILE=deep, 256 × 128 × 32768 calls per invariant; INV-13 emergent per `D-305-SENTINEL-01` — §3.C + §3.F).
- **EDGE_CASES tested:** 20 of 20 (EDGE-01..20 PROVEN at 10k runs each; EDGE-19 multi-day-RNG-stall stale-claim recovery + EDGE-20 burn-too-small dust floor extend the original 18 — §3.C aggregate).
- **NEW_FINDINGS:** 0 (Phase 307 unanimous-NEGATIVE; 0 FINDING_CANDIDATE; Task 6 elevation gate SKIPPED — §4).
- **KNOWN-ISSUES.md disposition:** UNMODIFIED at v44 close per `D-44N-KI-01` (§6).
- **D-08 5-Bucket Severity Rubric reference:** descriptive-only at v44 (rubric definitions per §2; the 7 SSTONK violations are structurally closed, not finding-class rated; zero F-44-NN blocks to bucket).
- **D-09 KI Gating Rubric reference:** descriptive-only at v44 (3-predicate test per §6 prose; no candidates evaluated; KNOWN-ISSUES.md UNMODIFIED).
- **In-band verdict-divergence attestation:** the ROADMAP/REQUIREMENTS `12 of 12` / `18 of 18` template strings are preserved in their source documents; the §3.F divergence-rationale row + §3.C in-band attestation are the record of the override to Phase 306 actual coverage (13 INV from `D-305-SENTINEL-01`; 20 EDGE from `D-305-DUST-FLOOR-01` + EDGE-19).

### 9b. 5-Phase Wave Summary

Phases 304 (SPEC — `6edc3967` + `315280b0` + `971688ba`; output `.planning/phases/304-*/304-SPEC.md` with INV-01..12 + SPEC-01..05 + EDGE-01..18) + 305 (IMPL — the v44.0 sStonk per-day redemption refactor; USER-APPROVED contract commit `213f9184` + AGENT-COMMITTED planning bundle `c6f7045b`/`47ab0b3f`; output `contracts/StakedDegenerusStonk.sol` per-day-keyed `pendingByDay[uint32]` + `pendingResolveDay` sentinel) + 306 (TST — `de75f620`/`333c803f`/`3143ea9c`/`d24a2487`/`b102bc0f`/`e0f7d77e`; 13 INV + 20 EDGE PROVEN at FOUNDRY_PROFILE=deep; AGENT-COMMITTED per `D-43N-TEST-COMMITS-AUTO-01`) + 307 (SWEEP — `b3fcee2c`/`a83ebc4c`/`3dc7cafd`/`5448cd5d`/`1352be27`/`e58b03b9`/`c7ef7219`; 3-skill HYBRID; unanimous-NEGATIVE; 72/72 disposition rows; 0 FINDING_CANDIDATE; Task 6 elevation gate SKIPPED per `D-307-AUDIT-ONLY-ROUTING-01`) + 308 (TERMINAL — this deliverable; SOURCE-TREE FROZEN; 2 AGENT-COMMITTED commits per `D-44N-CLOSURE-01`). The 5-phase FIX-MILESTONE wave shape (spec + impl + tst + sweep + terminal) is structurally COMPLETE. Closure signal: `MILESTONE_V44_AT_HEAD_6f0ba2963a10654ba554a8c333c5ee80c54a8349`.

### 9c. Closure Signal

**Closure signal:** `MILESTONE_V44_AT_HEAD_6f0ba2963a10654ba554a8c333c5ee80c54a8349`.

**5 FINDINGS verbatim locations (within `audit/FINDINGS-v44.0.md`):**
1. Frontmatter `closure_signal:` field (carries `MILESTONE_V44_AT_HEAD_6f0ba2963a10654ba554a8c333c5ee80c54a8349` resolved to the Commit 1 SHA at Commit 2).
2. §1 Audit Subject prose ("v44.0 closure HEAD is ... the emitted `MILESTONE_V44_AT_HEAD_6f0ba2963a10654ba554a8c333c5ee80c54a8349` signal").
3. §3.A row 2 sub-text ("v44 closure HEAD chains to this contract diff via `MILESTONE_V44_AT_HEAD_6f0ba2963a10654ba554a8c333c5ee80c54a8349`").
4. §9b 5-Phase Wave Summary closing line ("Closure signal: `MILESTONE_V44_AT_HEAD_6f0ba2963a10654ba554a8c333c5ee80c54a8349`").
5. §9c Closure Signal section canonical mention (this line) + propagation register listing.

(Frontmatter `audit_subject_head:` carries the raw SHA WITHOUT the `MILESTONE_V44_AT_HEAD_` prefix — the schema-mandated form per `D-297-FINDINGS-FRONTMATTER-01` lineage carry — and is the 6th SHA-bearing location, NOT counted in the 5-FINDINGS-verbatim-location set.)

**3 cross-document propagation targets (atomic 5-doc closure flip at Commit 2 per `D-44N-CLOSURE-01`):**
1. `.planning/ROADMAP.md` (v44.0 milestone summary section flipped active → ✅ SHIPPED + Phase 308 line flipped to `[x]` + Progress table 5/5; carries closure signal verbatim; v44.0 block collapsed into `<details>` archive per v43.0 pattern).
2. `.planning/STATE.md` (Last Shipped Milestone block rotated to v44.0; v43.0 → Prior Shipped; carries closure signal verbatim).
3. `.planning/MILESTONES.md` (v44.0 archive entry; carries closure signal verbatim).

The conventional bookkeeping pair `.planning/PROJECT.md` + `.planning/REQUIREMENTS.md` are updated atomically alongside (effecting the 5-doc closure flip per v43 P303 + v42 P297 + v41 P284 precedent); they update last-shipped-milestone reference (PROJECT.md) + requirements-complete-status entries (REQUIREMENTS.md) without carrying the closure-signal string verbatim. Pre-authorized per `D-44N-CLOSURE-PREAUTH-01` (Commit 2 fires autonomously after Commit 1 SHA capture; NO user-pause).

---

### 9d. Deferred to v45.0+ — Consolidated Handoff Register

Per `D-44N-CLOSURE-01` carry from `D-303-V44-HANDOFF-REGISTER-01` (mandatory; load-bearing for the v45.0+ plan-phase). v45.0+ plan-phase reads this register as primary input.

#### §9d.1 — Register overview

Total anchors: **135 anchors** = 112 D-43N-V44-HANDOFF-NN (HANDOFF-01..110 + HANDOFF-118..119; excludes HANDOFF-111..117 closed by v44) + 22 D-43N-V44-ADMA-NN + 1 D-43N-V44-ADMA-ERRATUM-01. Arithmetic: `119 - 7 + 22 + 1 = 135`. Equivalently `112 + 22 + 1 = 135` and `142 - 7 = 135`. v43.0 §9d shipped 142; v44 closure reduces to 135 after the HANDOFF-111..117 7-row V-184 subsumption cluster closure.

| Source | Anchor count | Range |
|--------|--------------|-------|
| FIXREC §M (RNGLOCK-FIXREC.md) — carried forward | 112 | D-43N-V44-HANDOFF-01..110 + HANDOFF-118..119 (excludes HANDOFF-111..117) |
| ADMA §4 (ADMIN-AUDIT.md) | 22 | D-43N-V44-ADMA-01..ADMA-22 (contiguous) |
| ADMA §4 (catalog erratum) | 1 | D-43N-V44-ADMA-ERRATUM-01 |
| **Total** | **135 anchors** | (load-bearing v45.0+ plan-phase input) |

#### §9d.2 — FIXREC handoff anchors (112 entries)

Per-ID summary line from RNGLOCK-FIXREC.md §M consolidated handoff register, carried forward from `audit/FINDINGS-v43.0.md` §9d.2 (119-row register) MINUS the 7 v44-closed (HANDOFF-111..117 — see §9d.3). v45.0+ plan-phase consumes as load-bearing input for FIX-NN sub-phase planning.

| Anchor | V-NNN | Slot family | Tactic | Tier | v45.0+ sub-phase scope |
|--------|-------|-------------|--------|------|------------------------|
| D-43N-V44-HANDOFF-01 | V-003 | S-02 `dailyHeroWagers[day][q]` | (b) snapshot | MEDIUM | `dailyIdx` snapshot/anchor at writer or consumer; closes V-003/V-004/V-005 with single diff. |
| D-43N-V44-HANDOFF-02 | V-004 | S-02 `dailyHeroWagers[day][q]` | (b) snapshot | MEDIUM | Parent-dispatcher reach; subsumed by HANDOFF-01 diff. |
| D-43N-V44-HANDOFF-03 | V-005 | S-02 `dailyHeroWagers[day][q]` | (b) snapshot | MEDIUM | Vault-routed reach; subsumed by HANDOFF-01 diff. |
| D-43N-V44-HANDOFF-04 | V-009 | S-05 `autoRebuyState[beneficiary]` | (a) verification-only | LOW (already gated) | Branch-coverage attestation; gate at DegenerusGame.sol:1513 verified. |
| D-43N-V44-HANDOFF-05 | V-010 | S-05 `autoRebuyState[beneficiary]` | (a) verification-only | LOW (already gated) | Branch-coverage attestation; gate at DegenerusGame.sol:1528. |
| D-43N-V44-HANDOFF-06 | V-011 | S-05 `autoRebuyState[beneficiary]` | (a) verification-only | LOW (already gated) | Branch-coverage attestation; gate at DegenerusGame.sol:1575 across both deactivate-cascade and full-activate arms. |
| D-43N-V44-HANDOFF-07 | V-012 | S-05 `autoRebuyState[beneficiary]` | (a) gate-add | LOW-MEDIUM (lens-adjusted) | Add `if (rngLockedFlag) revert RngLocked();` at `deactivateAfKingFromCoin:1641`; verify COIN-side reconciliation. |
| D-43N-V44-HANDOFF-08 | V-013 | S-05 `autoRebuyState[beneficiary]` | (a) gate-add | LOW-MEDIUM (lens-adjusted) | Add gate at `syncAfKingLazyPassFromCoin:1654`; verify COINFLIP-side reconciliation. |
| D-43N-V44-HANDOFF-09 | V-016 | S-06 `traitBurnTicket[lvl][trait]` | NO-OP | **STALE-CATALOG-ROW** | Phantom — `adminSeedTraitBucket` absent from source; line 2398 is `sampleTraitTickets` view. Mark CATALOG STALE-PHANTOM. |
| D-43N-V44-HANDOFF-10 | V-017 | S-06 `traitBurnTicket[lvl][trait]` | NO-OP | **STALE-CATALOG-ROW** | Phantom — `adminClearTraitBucket` absent from source; line 2427 is `sampleTraitTicketsAtLevel` view. Mark CATALOG STALE-PHANTOM. |
| D-43N-V44-HANDOFF-11 | V-018 | S-06 `traitBurnTicket[lvl][trait]` | NO-OP | **STALE-CATALOG-ROW** | Phantom — line 2510 is `getTickets` view; resolves §C.3.4 source-review placeholder. Mark CATALOG STALE-PHANTOM. |
| D-43N-V44-HANDOFF-12 | V-019 | S-07 `deityBySymbol[fullSymId]` | (a) gate-extend | MEDIUM | Add `if (gameOver) revert E();` after existing `:543` `rngLockedFlag` gate in `_purchaseDeityPass`. |
| D-43N-V44-HANDOFF-13 | V-024 | S-09 `prizePoolsPacked` | (a) gate-add | MEDIUM | Add top-level `rngLockedFlag` revert at MintModule.purchase/purchaseCoin/purchaseBurnieLootbox (3 entries). |
| D-43N-V44-HANDOFF-14 | V-025 | S-09 `prizePoolsPacked` | (a) gate-add | MEDIUM | Add top-level `rngLockedFlag` revert at WhaleModule.purchaseWhaleBundle / purchaseLazyPass (2 entries). |
| D-43N-V44-HANDOFF-15 | V-026 | S-09 `prizePoolsPacked` | (a) verification-only | LOW (already gated) | Branch-coverage attestation; gate at WhaleModule.sol:543. |
| D-43N-V44-HANDOFF-16 | V-027 | S-09 `prizePoolsPacked` | (a) gate-add | MEDIUM-HIGH | Add `rngLockedFlag` gate at `DegenerusGame.recordDecBurn:1029` (GAME-side); covers BurnieCoin decimatorBurn callback path. |
| D-43N-V44-HANDOFF-17 | V-030 | S-09 `prizePoolsPacked` (adjacent) | (a) gate-add | LOW (downstream gated) | Add explicit top-level gate at WhaleModule.claimWhalePass:957 for diagnostic clarity. |
| D-43N-V44-HANDOFF-18 | V-031 | S-09 `prizePoolsPacked` | (a) gate-add | **HIGH** | Add `rngLockedFlag` revert at `_placeDegeneretteBetCore:405`; cheapest per-tx inflation surface. |
| D-43N-V44-HANDOFF-19 | V-032 | S-09 `prizePoolsPacked` (lootbox payout) | (b) snapshot | HIGH | Snapshot prizePool at lootbox-buy-time, not open-time; per-index snapshot field in `lootboxBaseLevelPacked` packing. |
| D-43N-V44-HANDOFF-20 | V-043 | S-14 sDGNRS `poolBalances[Reward]` | (b) snapshot | MEDIUM-HIGH (lens-adjusted) | Snapshot at `_swapAndFreeze`; `_handleSoloBucketWinner:1493` reads snapshot. Closes V-043+V-045+V-046 with single field. |
| D-43N-V44-HANDOFF-21 | V-045 | S-14 sDGNRS `poolBalances[Reward]` | (b) snapshot (shared) | LOW (catalog-discipline) | Subsumed by HANDOFF-20 (admin/init writers structurally inactive). |
| D-43N-V44-HANDOFF-22 | V-046 | S-14 sDGNRS `poolBalances[Reward]` | (b) snapshot (shared) | LOW (consumer-disambiguated) | **OZ-carveout** — fix lands in `contracts/` per `D-298-OZ-CARVEOUT-01`; subsumed by HANDOFF-20. Lone non-`contracts/` writer-class VIOLATION in entire catalog. |
| D-43N-V44-HANDOFF-23 | V-047 | S-15 sDGNRS `poolBalances[Lootbox]` | (b) snapshot | **PENDING-VERIFICATION** (Phase 302 → NEGATIVE_RESULT_ONLY drain-shape + ACCEPTED_DESIGN frontrun-shape) | Per-index `lootboxPoolSnapshotByIndex` at `_finalizeLootboxRng`. v45.0+ plan-phase consumes per Phase 302 disposition. |
| D-43N-V44-HANDOFF-24 | V-048 | S-15 sDGNRS `poolBalances[Lootbox]` | (b) snapshot (shared) | **PENDING-VERIFICATION** (resolved) | Subsumed by HANDOFF-23 (BURNIE-path sibling). |
| D-43N-V44-HANDOFF-25 | V-050 | S-15 sDGNRS `poolBalances[Lootbox]` | (b) snapshot | **PENDING-VERIFICATION** (resolved) | sStonk burn-submission snapshot mirroring `activityScore`; extend `PendingRedemption` struct + `IDegenerusGame.resolveRedemptionLootbox` signature. |
| D-43N-V44-HANDOFF-26 | V-051 | S-15 sDGNRS `poolBalances[Lootbox]` | per-callsite split | LOW (MintPath subsumed) | AdvanceStack=EXEMPT (no fix); MintPath=subsumed by HANDOFF-13; AdminPath=forward-attestation only. |
| D-43N-V44-HANDOFF-27 | V-054 | S-16 `claimablePool` | (a) gate-add | MEDIUM | `_livenessTriggered() && !gameOver` at `claimDecimatorJackpot:321`. |
| D-43N-V44-HANDOFF-28 | V-055 | S-16 `claimablePool` | (a) verification-only | LOW (already gated) | Branch-coverage; gate present at `MintModule:877/:906/:1215`. |
| D-43N-V44-HANDOFF-29 | V-057 | S-16 `claimablePool` | (a) gate-add | MEDIUM | `_livenessTriggered()` at `placeDegeneretteBet:367`. |
| D-43N-V44-HANDOFF-30 | V-058 | S-16 `claimablePool` | (a) gate-add | HIGH | `_livenessTriggered()` at `resolveBets:389`; preserves EXEMPT-VRFCALLBACK branch. |
| D-43N-V44-HANDOFF-31 | V-063 | S-16 `claimablePool` | (a) gate-add | **HIGH (per §6.4 amendment — CONFIRMED-PARTICIPATING-AT-GAME-OVER-DRAIN)** | `_livenessTriggered() && !gameOver` at `_claimWinningsInternal:1399`. Also closes V-073 (HANDOFF-40). |
| D-43N-V44-HANDOFF-32 | V-064 | S-16 `claimablePool` | (a) verification-only | LOW (already gated) | Branch-coverage; gate present at `MintModule:877/:906/:1215`. |
| D-43N-V44-HANDOFF-33 | V-065 | S-16 `claimablePool` | (a) gate-add | HIGH | `_livenessTriggered() && !gameOver` at `resolveRedemptionLootbox:1721`; mirror of HANDOFF-31. |
| D-43N-V44-HANDOFF-34 | V-066 | S-17 `pendingRedemptionEthValue` | (a) verification-only | LOW (already gated) | Assert paired-gate at sStonk:491-:492 covers writer at :789. |
| D-43N-V44-HANDOFF-35 | V-068 | S-17 `pendingRedemptionEthValue` | subsumption | (subsumed by V-184; RESOLVED-AT-V44 transitive) | Cross-referenced V-184 (HANDOFF-111). With V-184 closed at v44, this transitive reference is mooted; no independent fix. |
| D-43N-V44-HANDOFF-36 | V-069 | S-18 `deityPassOwners` | (a) gate-extend | MEDIUM | Extend `_purchaseDeityPass` gate to revert when any lootbox RNG word is fresh-but-unconsumed. |
| D-43N-V44-HANDOFF-37 | V-070 | S-19 `deityPassPurchasedCount[owner]` | (a) gate-extend (shared) | MEDIUM | Subsumed by HANDOFF-36. |
| D-43N-V44-HANDOFF-38 | V-071 | S-20 `address(this).balance` (ETH inflow) | (b) snapshot | HIGH | Snapshot `totalFunds` at `_gameOverEntropy`; closes both V-071 and V-080. |
| D-43N-V44-HANDOFF-39 | V-072 | S-20 `address(this).balance` (purchase inflate) | (a) verification-only | LOW (already gated) | Assert `_livenessTriggered() || rngLockedFlag` gate on every payable purchase entry. |
| D-43N-V44-HANDOFF-40 | V-073 | S-20 `address(this).balance` (claimWinnings outflow) | (a) gate-add (shared) | HIGH | Subsumed by HANDOFF-31 — same `_claimWinningsInternal:1400` gate. |
| D-43N-V44-HANDOFF-41 | V-074 | S-20 `address(this).balance` (cross-contract sister withdraw) | (a) verification | MEDIUM | Verify transitive sister-contract gate coverage; v45.0+ plan-phase enumerates sister-contract entry points. |
| D-43N-V44-HANDOFF-42 | V-080 | S-21 `stETH.balanceOf(game)` | (b) snapshot (shared) | HIGH | Subsumed by HANDOFF-38 — single `gameOverFundsSnapshot` field. |
| D-43N-V44-HANDOFF-43 | V-081 | S-22 `lootboxEvBenefitUsedByLevel` | (b) snapshot | LOW / ACCEPTABLE-DESIGN (lens-adjusted) | Snapshot cap at allocation time into `lootboxEvCapAtAllocation`; consumer reads snapshot. |
| D-43N-V44-HANDOFF-44 | V-082 | S-22 `lootboxEvBenefitUsedByLevel` | (b) snapshot (shared) | LOW / ACCEPTABLE-DESIGN | Same snapshot as HANDOFF-43; BURNIE-path. |
| D-43N-V44-HANDOFF-45 | V-084 | S-22 `lootboxEvBenefitUsedByLevel` | (b) snapshot | LOW / ACCEPTABLE-DESIGN | Snapshot at sStonk burn submission alongside `activityScore`. |
| D-43N-V44-HANDOFF-46 | V-088 | S-24 `lootboxEth[index][player]` | (b) stack-capture | LOW (self-zero is intended state machine) | Stack-capture at `openLootBox` entry; closes V-088 + V-094 + V-097 + V-100. |
| D-43N-V44-HANDOFF-47 | V-089 | S-24 `lootboxEth[index][player]` | (a) gate-add | MEDIUM | `RngLocked` revert at `MintModule._allocateLootbox:982`. Single gate covers 5 V-NNN (V-089/V-091/V-095/V-098/V-101). |
| D-43N-V44-HANDOFF-48 | V-090 | S-24 `lootboxEth[index][player]` | (a) gate-add | MEDIUM | Mirror MINTCLN gate at `WhaleModule._whaleLootboxAllocate:845`. Single gate covers 5 V-NNN (V-090/V-093/V-096/V-099/V-102). |
| D-43N-V44-HANDOFF-49 | V-091 | S-25 `lootboxDay[index][player]` | (a) gate-add (shared) | MEDIUM | Subsumed by HANDOFF-47. |
| D-43N-V44-HANDOFF-50 | V-092 | S-25 `lootboxDay[index][player]` | (a) gate-add | MEDIUM | `RngLocked` revert at `MintModule._purchaseBurnieLootboxFor:1384`. Closes V-092 + V-104. |
| D-43N-V44-HANDOFF-51 | V-093 | S-25 `lootboxDay[index][player]` | (a) gate-add (shared) | MEDIUM | Subsumed by HANDOFF-48. |
| D-43N-V44-HANDOFF-52 | V-094 | S-26 `lootboxBaseLevelPacked` | (b) stack-capture (shared) | LOW | Subsumed by HANDOFF-46. |
| D-43N-V44-HANDOFF-53 | V-095 | S-26 `lootboxBaseLevelPacked` | (a) gate-add (shared) | MEDIUM | Subsumed by HANDOFF-47. |
| D-43N-V44-HANDOFF-54 | V-096 | S-26 `lootboxBaseLevelPacked` | (a) gate-add (shared) | MEDIUM | Subsumed by HANDOFF-48. |
| D-43N-V44-HANDOFF-55 | V-097 | S-27 `lootboxEvScorePacked` | (b) stack-capture (shared) | LOW | Subsumed by HANDOFF-46. |
| D-43N-V44-HANDOFF-56 | V-098 | S-27 `lootboxEvScorePacked` | (a) gate-add (shared) | HIGH (activity-score-influencing) | Subsumed by HANDOFF-47. |
| D-43N-V44-HANDOFF-57 | V-099 | S-27 `lootboxEvScorePacked` | (a) gate-add (shared) | HIGH (activity-score-influencing) | Subsumed by HANDOFF-48. |
| D-43N-V44-HANDOFF-58 | V-100 | S-28 `lootboxDistressEth` | (b) stack-capture (shared) | LOW | Subsumed by HANDOFF-46. |
| D-43N-V44-HANDOFF-59 | V-101 | S-28 `lootboxDistressEth` | (a) gate-add (shared) | MEDIUM | Subsumed by HANDOFF-47. |
| D-43N-V44-HANDOFF-60 | V-102 | S-28 `lootboxDistressEth` | (a) gate-add (shared) | MEDIUM | Subsumed by HANDOFF-48. |
| D-43N-V44-HANDOFF-61 | V-103 | S-29 `lootboxBurnie` | (b) stack-capture | LOW | Stack-capture at `openBurnieLootBox:614`. |
| D-43N-V44-HANDOFF-62 | V-104 | S-29 `lootboxBurnie` | (a) gate-add (shared) | MEDIUM | Subsumed by HANDOFF-50. |
| D-43N-V44-HANDOFF-63 | V-105 | S-30 `presaleStatePacked` | (b) snapshot | MEDIUM | Define `LB_PRESALE_BIT` in `lootboxBaseLevelPacked` packed layout; emit at allocation, read at consumer presale arm. |
| D-43N-V44-HANDOFF-64 | V-109 | S-32 `mintPacked_` (activity score) | (b) snapshot | HIGH (activity-score-influencing) | Route `_lootboxEvMultiplierBps` to read `lootboxEvScorePacked[index][player]` rather than live `_playerActivityScore`. |
| D-43N-V44-HANDOFF-65 | V-110 | S-32 `mintPacked_` | (b) snapshot | HIGH (activity-score-influencing) | Define snapshot encoding for full activity-score result; route 3 callsites' downstream consumer SLOADs. |
| D-43N-V44-HANDOFF-66 | V-111 | S-32 `mintPacked_` (BoonModule.consumeActivityBoon) | (c) pre-lock reorder | MEDIUM | Relocate `_consumeActivityBoon` selector dispatch inside `_resolveLootboxCommon` to post-roll position. |
| D-43N-V44-HANDOFF-67 | V-112 | S-32 `mintPacked_` (BoonModule._applyBoon whale-pass) | (b) snapshot | MEDIUM | Ensure activity-score snapshot includes whale-pass / frozen-until / has-deity-pass bits at allocation. |
| D-43N-V44-HANDOFF-68 | V-113 | S-32 `mintPacked_` (WhaleModule._buyWhaleBundle*) | (b) snapshot | MEDIUM | Activity-score snapshot widening covers WhaleModule purchase paths (8 callsites). |
| D-43N-V44-HANDOFF-69 | V-114 | S-32 `mintPacked_` (WhaleModule._buyDeityPass) | (b) snapshot | MEDIUM | Activity-score snapshot widening. |
| D-43N-V44-HANDOFF-70 | V-117 | S-32 `mintPacked_` (`_applyWhalePassStats`) | (b) snapshot | HIGH (activity-score-influencing) | Activity-score snapshot widening covers lootbox boon path entries. |
| D-43N-V44-HANDOFF-71 | V-120 | S-33 `boonPacked` (LootboxModule._applyBoon) | (b) snapshot | MEDIUM | Boon-state snapshot at allocation; consumer reads snapshot. |
| D-43N-V44-HANDOFF-72 | V-121 | S-33 `boonPacked` (WhaleModule._buyWhaleBundle*) | (b) snapshot | MEDIUM | Snapshot widening across WhaleModule boon writes. |
| D-43N-V44-HANDOFF-73 | V-122 | S-33 `boonPacked` (MintModule._applyLootboxBoostOnPurchase) | (b) snapshot | MEDIUM | Snapshot widening at MintModule boon write. |
| D-43N-V44-HANDOFF-74 | V-123 | S-33 `boonPacked` (BoonModule.checkAndClearExpiredBoon) | (b) snapshot | MEDIUM | Snapshot widening at expired-boon clear. |
| D-43N-V44-HANDOFF-75 | V-124 | S-33 `boonPacked` slot1 (BoonModule.consumeActivityBoon) | (b) snapshot | MEDIUM | Snapshot widening at activity-boon consume. |
| D-43N-V44-HANDOFF-76 | V-125 | S-33 `boonPacked` (BoonModule other-externals) | (a) gate-add (per-callsite) | MEDIUM | Per-callsite verification; apply tactic-(a) gate at DegenerusGame dispatcher level for each BoonModule external. |
| D-43N-V44-HANDOFF-77 | V-127 | S-35 `lastPurchaseDay` (MintModule purchase) | NO-OP | **RESOLVED-AS-PHANTOM** | No current source writer exists. Close as RESOLVED-AS-PHANTOM unless re-attestation finds a new writer. |
| D-43N-V44-HANDOFF-78 | V-137 | S-38 `rngRequestTime` (governance) | (c) rotation queue+apply | **GOVERNANCE-HIGH (lens-adjusted)** | Define `pendingVrfRotationPacked`; split `updateVrfCoordinatorAndSub` into queue + apply. Closes 5 governance rows (HANDOFF-78/85/87/89/91). |
| D-43N-V44-HANDOFF-79 | V-140 | S-41 affiliate cross-contract (LABEL-REFINEMENT) | (b) snapshot | MEDIUM | Activity-score snapshot widening; route `_lootboxEvMultiplierBps` + affiliate-derived caps to read from `lootboxEvScorePacked[index][player]`. |
| D-43N-V44-HANDOFF-80 | V-141 | S-42 questView cross-contract | (b) snapshot | MEDIUM | Extend `_allocateLootbox` to snapshot questStreak; route `_resolveLootboxCommon` to read snapshot. |
| D-43N-V44-HANDOFF-81 | V-142 | S-43 `degeneretteBets[player][nonce]` | (a) verification-only (CONDITIONAL) | LOW (already gated) | NO sub-phase required if gate-coverage confirmed; CONDITIONAL re-attest only if gate-bypass surfaces. |
| D-43N-V44-HANDOFF-82 | V-147 | S-45 `prizePoolPendingPacked` (DegeneretteModule frozen-branch) | (a) gate-add | MEDIUM | Add `if (rngLockedFlag) revert RngLocked();` at top of `_placeDegeneretteBetCore`. |
| D-43N-V44-HANDOFF-83 | V-149 | S-45 `prizePoolPendingPacked` (MintModule frozen-branch — LABEL-REFINEMENT) | (a) gate-add | MEDIUM | AUTHOR new `prizePoolFrozen && rngLockedFlag` revert at `_purchaseFor` top. |
| D-43N-V44-HANDOFF-84 | V-153 | S-46 `lootboxRngPacked.LR_MID_DAY` (commitment-side) | RECLASSIFY | **RESOLVED-AS-RECLASSIFIED** | Scope-expand `EXEMPT-RETRYLOOTBOXRNG` envelope; ZERO contract change. v45.0+ plan-phase has NO sub-phase obligation. |
| D-43N-V44-HANDOFF-85 | V-155 | S-46 `lootboxRngPacked.LR_MID_DAY` (governance) | (c) rotation queue+apply (shared) | GOVERNANCE-HIGH | Subsumed by HANDOFF-78. |
| D-43N-V44-HANDOFF-86 | V-156 | S-47 `vrfCoordinator` (wireVrf) | (d) immutable / one-shot lock | **GOVERNANCE-HIGH** | `wireVrf` one-shot lock. Closes 3 wireVrf rows (HANDOFF-86/88/90). |
| D-43N-V44-HANDOFF-87 | V-157 | S-47 `vrfCoordinator` (governance) | (c) rotation queue+apply (shared) | GOVERNANCE-HIGH | Subsumed by HANDOFF-78. |
| D-43N-V44-HANDOFF-88 | V-158 | S-48 `vrfSubscriptionId` (wireVrf) | (d) one-shot lock (shared) | GOVERNANCE-HIGH | Subsumed by HANDOFF-86. |
| D-43N-V44-HANDOFF-89 | V-159 | S-48 `vrfSubscriptionId` (governance) | (c) rotation queue+apply (shared) | GOVERNANCE-HIGH | Subsumed by HANDOFF-78. |
| D-43N-V44-HANDOFF-90 | V-160 | S-49 `vrfKeyHash` (wireVrf) | (d) one-shot lock (shared) | GOVERNANCE-HIGH | Subsumed by HANDOFF-86. |
| D-43N-V44-HANDOFF-91 | V-161 | S-49 `vrfKeyHash` (governance) | (c) rotation queue+apply (shared) | GOVERNANCE-HIGH | Subsumed by HANDOFF-78. |
| D-43N-V44-HANDOFF-92 | V-168 | S-52 `ticketQueue[rk]` (purchaseWhaleBundle) | (a) gate-add | MEDIUM | `rngLockedFlag` revert at `_purchaseWhaleBundle` entry; co-located with HANDOFF-101 (V-179.A). |
| D-43N-V44-HANDOFF-93 | V-169 | S-52 `ticketQueue[rk]` (purchaseLazyPass) | (a) gate-add | MEDIUM | `rngLockedFlag` revert at `_purchaseLazyPass` entry; co-located with HANDOFF-102 (V-179.B). |
| D-43N-V44-HANDOFF-94 | V-170 | S-52 `ticketQueue[rk]` (purchaseDeityPass) | (a) verification-only | LOW (already gated) | Verify `WhaleModule:543` gate remains in place; no patch. Co-located with HANDOFF-103 (V-179.C). |
| D-43N-V44-HANDOFF-95 | V-171 | S-52 `ticketQueue[rk]` (openLootBox) | (a) gate-add | MEDIUM | `rngLockedFlag` revert at `openLootBox` entry; co-located with HANDOFF-104 (V-179.D). |
| D-43N-V44-HANDOFF-96 | V-172 | S-52 `ticketQueue[rk]` (openBurnieLootBox) | (a) gate-add | MEDIUM | `rngLockedFlag` revert at `openBurnieLootBox` entry; co-located with HANDOFF-105 (V-179.E). |
| D-43N-V44-HANDOFF-97 | V-174 | S-52 `ticketQueue[rk]` (_purchaseFor) | (a) gate-add | MEDIUM | `rngLockedFlag` revert at `purchase`/`purchaseCoin`/`purchaseBurnieLootbox` entries; co-located with HANDOFF-106 (V-179.F). |
| D-43N-V44-HANDOFF-98 | V-175 | S-52 `ticketQueue[rk]` (_awardDecimatorLootbox) | (a) gate-add | MEDIUM | `rngLockedFlag` revert at `claimDecimatorJackpot` entry; co-located with HANDOFF-107 (V-179.G). |
| D-43N-V44-HANDOFF-99 | V-176 | S-52 `ticketQueue[rk]` (claimWhalePass) | (a) gate-add | MEDIUM | `rngLockedFlag` revert at `claimWhalePass` entry; co-located with HANDOFF-108 (V-179.H). |
| D-43N-V44-HANDOFF-100 | V-177 | S-52 `ticketQueue[rk]` (_redeemWhalePassRange) | (a) gate-add (shared) | MEDIUM | Subsumed by HANDOFF-99; co-located with HANDOFF-109 (V-179.I). |
| D-43N-V44-HANDOFF-101 | V-179.A | S-53 `ticketsOwedPacked[rk][player]` (purchaseWhaleBundle) | (a) gate-add (shared) | MEDIUM | Subsumed by HANDOFF-92 (same gate). |
| D-43N-V44-HANDOFF-102 | V-179.B | S-53 `ticketsOwedPacked` (purchaseLazyPass) | (a) gate-add (shared) | MEDIUM | Subsumed by HANDOFF-93. |
| D-43N-V44-HANDOFF-103 | V-179.C | S-53 `ticketsOwedPacked` (purchaseDeityPass) | (a) verification-only | LOW (already gated) | Subsumed by HANDOFF-94. |
| D-43N-V44-HANDOFF-104 | V-179.D | S-53 `ticketsOwedPacked` (openLootBox) | (a) gate-add (shared) | MEDIUM | Subsumed by HANDOFF-95. |
| D-43N-V44-HANDOFF-105 | V-179.E | S-53 `ticketsOwedPacked` (openBurnieLootBox) | (a) gate-add (shared) | MEDIUM | Subsumed by HANDOFF-96. |
| D-43N-V44-HANDOFF-106 | V-179.F | S-53 `ticketsOwedPacked` (_purchaseFor) | (a) gate-add (shared) | MEDIUM | Subsumed by HANDOFF-97. |
| D-43N-V44-HANDOFF-107 | V-179.G | S-53 `ticketsOwedPacked` (_awardDecimatorLootbox) | (a) gate-add (shared) | MEDIUM | Subsumed by HANDOFF-98. |
| D-43N-V44-HANDOFF-108 | V-179.H | S-53 `ticketsOwedPacked` (claimWhalePass) | (a) gate-add (shared) | MEDIUM | Subsumed by HANDOFF-99. |
| D-43N-V44-HANDOFF-109 | V-179.I | S-53 `ticketsOwedPacked` (_redeemWhalePassRange) | (a) gate-add (shared) | MEDIUM | Subsumed by HANDOFF-100. |
| D-43N-V44-HANDOFF-110 | V-182 | S-54 `bountyOwedTo` (BurnieCoinflip.depositCoinflip) | (a) gate-tighten | MEDIUM | Convert `:664` silent-skip to fail-closed revert for bounty-eligible deposits during rngLock; pattern: `BurnieCoinflip:730` `RngLocked` convention. |
| D-43N-V44-HANDOFF-118 | V-201 | S-66 `decBurn[lvl][player].burn` | (a) gate-add | MEDIUM | Add `decClaimRounds[lvl].poolWei == 0` gate at `recordDecBurn` entry. |
| D-43N-V44-HANDOFF-119 | V-202 | S-67 `terminalDecBucketBurnTotal[bucketKey]` | (a) gate-add | MEDIUM | Add `rngWordByDay[currentDay] == 0` gate at `recordTerminalDecBurn` entry. |

**Total FIXREC anchors carried forward to v45.0+:** 112 (HANDOFF-01..110 + HANDOFF-118..119; HANDOFF-111..117 closed at v44 — §9d.3). **v45.0+ sub-phase budget after subsumption (per FIXREC §0.6 + §M):** ~24 sub-phases (the v43 ~25-sub-phase budget minus the V-184 PRIORITY-1 sub-phase, now closed).

#### §9d.3 — V-184 + HANDOFF-111..117 CLOSURE attestation (NEW vs v43 §9d)

The 7 v44-closed FIXREC anchors (removed from the §9d.2 carry-forward register), closed via the single structural refactor `213f9184` per the FIXREC §0.6 subsumption map (see §3.D for full disposition):

| Anchor | V-NNN | Slot family | v44 closure mechanism |
|--------|-------|-------------|------------------------|
| D-43N-V44-HANDOFF-111 | **V-184** | S-56 `redemptionPeriodIndex` | **CLOSED-AT-V44** — per-day keying makes the cross-day re-roll overwrite primitive structurally unreachable; INV-13 single-pool sentinel PROVEN; EDGE-07 attack-reproduction asserts no overwrite; TST-05 strict byte-identity assertion PASS (`b102bc0f`). |
| D-43N-V44-HANDOFF-112 | V-186 | S-56 `pendingRedemptionEthBase` | **CLOSED-AT-V44** — collateral via V-184 subsumption fan-out (per-day keyed `pendingByDay[uint32].ethBase`). |
| D-43N-V44-HANDOFF-113 | V-188 | S-56 `pendingRedemptionBurnieBase` | **CLOSED-AT-V44** — collateral via V-184 subsumption fan-out. |
| D-43N-V44-HANDOFF-114 | V-190 | S-56 `pendingRedemptionBurnie` | **CLOSED-AT-V44** — collateral via V-184 subsumption fan-out. |
| D-43N-V44-HANDOFF-115 | V-191 | S-56 `pendingRedemptions[player]` writes | **CLOSED-AT-V44** — collateral via V-184 subsumption fan-out. |
| D-43N-V44-HANDOFF-116 | V-192 | S-56 `pendingRedemptions[player]` delete | **CLOSED-AT-V44** — collateral via V-184 subsumption fan-out (SPEC-04(c) `delete pendingByDay[dayToResolve]` at resolve). |
| D-43N-V44-HANDOFF-117 | V-193 | S-56 `pendingRedemptions[player]` partial clear | **CLOSED-AT-V44** — collateral via V-184 subsumption fan-out. |

**Closure verdict fragment:** `7 of 7 SSTONK_VIOLATIONS RESOLVED_AT_V44`. These 7 anchors are NOT carried into the v45.0+ register; the §9d.2 carry-forward count drops from 119 to 112 accordingly.

#### §9d.4 — ADMA handoff anchors (22 entries + 1 ERRATUM)

Carried verbatim from `audit/FINDINGS-v43.0.md` §9d.3. v45.0+ plan-phase consumes for ADM-NN contract-change sub-phase planning. (Note: ADMA-21 + ADMA-22 reference `D-43N-V44-HANDOFF-111` S-56 re-resolution lock at the vault-routed sDGNRS burn/claim underlying; with V-184 structurally closed at v44, that underlying lock is now realized by the per-day refactor — the vault-routed verification reduces to confirming the per-day `pendingByDay` write-once invariant holds through the `DegenerusVault` dispatch.)

| Anchor | Admin fn (file:line) | Slot(s) reached | Admin-class | Tactic | v45.0+ sub-phase scope |
|---|---|---|---|---|---|
| D-43N-V44-ADMA-01 | DegenerusGameAdvanceModule.wireVrf @ AdvanceModule.sol:498 | S-47, S-48, S-49 | governance | (d) immutable | Seal `wireVrf` post-init via one-shot flag; cross-refs catalog V-156/V-158/V-160 (HANDOFF-86 closes 3 wireVrf rows). |
| D-43N-V44-ADMA-02 | DegenerusGameAdvanceModule.updateVrfCoordinatorAndSub @ AdvanceModule.sol:1677 | S-47, S-48, S-49, S-38, S-46 LR_MID_DAY | governance | (c) pre-lock reorder | Queue mid-stall rotations until callback delivers or 12h+ timeout; cross-refs HANDOFF-78 (closes 5 governance rows). |
| D-43N-V44-ADMA-03 | DegenerusGame.adminSwapEthForStEth @ DegenerusGame.sol:1805 | S-20, S-21 | governance | (a) rngLockedFlag revert | Add `if (rngLockedFlag) revert RngLocked();` at function entry; cross-refs V-072/V-074/V-080. |
| D-43N-V44-ADMA-04 | DegenerusGame.adminStakeEthForStEth @ DegenerusGame.sol:1826 | S-20, S-21 | governance | (a) rngLockedFlag revert | Add `rngLockedFlag` revert at function entry; admin reach does NOT inherit V-079 EXEMPT classification. |
| D-43N-V44-ADMA-05 | DegenerusAdmin.swapGameEthForStEth @ DegenerusAdmin.sol:631 | S-20 | governance | (a) rngLockedFlag revert | Add `rngLockedFlag` revert at vault-owner-facing entry; second gate at underlying `gameAdmin.adminSwapEthForStEth` (ADMA-03). |
| D-43N-V44-ADMA-06 | GNRUS.setCharity @ GNRUS.sol:378 | (cross-contract gap — GNRUS `currentSlate[slot]`; downstream feeds S-14) | governance | (a) rngLockedFlag revert | Add cross-contract `game.rngLocked()` revert at function entry; OPTIONAL catalog-extension. (Phase 302/307 ALREADY-DOCUMENTED.) |
| D-43N-V44-ADMA-07 | DegenerusVault.gamePurchase @ DegenerusVault.sol:513 | S-09, S-30, S-24..S-29, S-32, S-35, S-52, S-53 | general | (a) rngLockedFlag revert at underlying | Verify HANDOFF-13 gate at MintModule.purchase covers vault-routed dispatcher reach. |
| D-43N-V44-ADMA-08 | DegenerusVault.gamePurchaseTicketsBurnie @ DegenerusVault.sol:534 | S-09, S-32, S-25, S-29, S-52, S-53 | general | (a) rngLockedFlag revert at underlying | Verify HANDOFF-13 gate at MintModule.purchaseCoin covers vault-routed. |
| D-43N-V44-ADMA-09 | DegenerusVault.gamePurchaseBurnieLootbox @ DegenerusVault.sol:543 | S-29, S-25, S-52, S-53 | general | (a) rngLockedFlag revert at underlying | Verify HANDOFF-13 covers vault-routed BURNIE lootbox purchase. |
| D-43N-V44-ADMA-10 | DegenerusVault.gameOpenLootBox @ DegenerusVault.sol:551 | S-22, S-24..S-29, S-52 | general | (b) snapshot at allocation | Verify HANDOFF-43..46/52/55/58/95 snapshot-at-allocation covers vault-routed open. |
| D-43N-V44-ADMA-11 | DegenerusVault.gamePurchaseDeityPassFromBoon @ DegenerusVault.sol:561 | S-07, S-18, S-19, S-32, S-34, S-52, S-53 | general | (a) rngLockedFlag revert at underlying | Verify HANDOFF-12/36/37 gate at WhaleModule._purchaseDeityPass covers vault-routed. |
| D-43N-V44-ADMA-12 | DegenerusVault.gameDegeneretteBet @ DegenerusVault.sol:594 | S-02, S-43, S-09, S-45 | general | (b) day-key freeze (S-02) + (a) rngLockedFlag revert (rest) | Verify HANDOFF-03/18/81/82 tactic-mix covers vault-routed degenerette bet. |
| D-43N-V44-ADMA-13 | DegenerusVault.gameSetAutoRebuy @ DegenerusVault.sol:627 | S-05 | general | (a) rngLockedFlag revert at underlying | Verify HANDOFF-04 gate at `_setAutoRebuy:1513` covers vault-routed reach. |
| D-43N-V44-ADMA-14 | DegenerusVault.gameSetAutoRebuyTakeProfit @ DegenerusVault.sol:634 | S-05 | general | (a) rngLockedFlag revert at underlying | Verify HANDOFF-05 gate at `_setAutoRebuyTakeProfit:1528` covers vault-routed reach. |
| D-43N-V44-ADMA-15 | DegenerusVault.gameSetAfKingMode @ DegenerusVault.sol:643 | S-05 | general | (a) rngLockedFlag revert at underlying | Verify HANDOFF-06 gate at `_setAfKingMode:1575` covers vault-routed reach. |
| D-43N-V44-ADMA-16 | DegenerusVault.coinDepositCoinflip @ DegenerusVault.sol:662 | S-55 | general | (a) bounty-arming gate at underlying | Verify HANDOFF-110 fail-closed extension at BurnieCoinflip._addDailyFlip:681 covers vault-routed reach. |
| D-43N-V44-ADMA-17 | DegenerusVault.coinDecimatorBurn @ DegenerusVault.sol:677 | S-09, S-66 | general | (a) rngLockedFlag revert at underlying | Verify HANDOFF-16/118 gates cover vault-routed decimator burn. |
| D-43N-V44-ADMA-18 | DegenerusVault.gameClaimWinnings @ DegenerusVault.sol:575 | S-16, S-20 | general | (a) rngLockedFlag revert at underlying | Verify HANDOFF-31/40 gate at DegenerusGame.claimWinnings covers vault-routed. |
| D-43N-V44-ADMA-19 | DegenerusVault.gameClaimWhalePass @ DegenerusVault.sol:581 | S-09, S-52, S-53 | general | (a) rngLockedFlag revert at underlying | Verify HANDOFF-17/99 covers vault-routed whale-pass claim. |
| D-43N-V44-ADMA-20 | DegenerusVault.jackpotsClaimDecimator @ DegenerusVault.sol:708 | S-16 | general | (a) liveness gate at underlying | Verify HANDOFF-27 liveness gate at `_awardDecimatorLootbox` covers vault-routed decimator claim. |
| D-43N-V44-ADMA-21 | DegenerusVault.sdgnrsBurn @ DegenerusVault.sol:719 | S-17, S-56, S-57, S-58, S-59, S-60 | general | (a) S-56 per-day write-once at underlying | V-184 S-56 surface CLOSED-AT-V44; verify the per-day `pendingByDay` write-once invariant holds through the vault-routed sDGNRS burn dispatch. |
| D-43N-V44-ADMA-22 | DegenerusVault.sdgnrsClaimRedemption @ DegenerusVault.sol:725 | S-17, S-60 | general | (a) S-56 per-day write-once at underlying | V-184 S-56 surface CLOSED-AT-V44; verify per-day `pendingByDay` write-once invariant holds through the vault-routed sDGNRS claim dispatch. |
| D-43N-V44-ADMA-ERRATUM-01 | (catalog erratum, no admin fn) | S-06 (phantom) | n/a | catalog-correction | RNGLOCK-CATALOG.md §15 rows 154/155/156 + §16 V-016/V-017/V-018 + §C.3.2/C.3.3 enumerate phantom admin trait-bucket writers; source verification (`grep "adminSeedTraitBucket\|adminClearTraitBucket" contracts/` returns 0 hits) confirms absent from source; actual S-06 writer `_raritySymbolBatch` is INTERNAL-only EXEMPT-ADVANCEGAME. v45.0+ plan-phase MUST NOT spend a sub-phase on these phantom functions. |

**Total ADMA anchors:** 22 numbered (ADMA-01..ADMA-22 contiguous) + 1 ERRATUM-01 = 23 entries.

**ADMA admin-class breakdown:** 6 governance (ADMA-01..06) + 16 general (ADMA-07..22).

#### §9d.5 — Subsumption map carry-forward (per FIXREC §0.6)

Subsumption clusters where one fix closes multiple catalog rows. v45.0+ plan-phase reads this map to schedule single-fix multi-row-closure sub-phases:

1. **HANDOFF-111 V-184 cluster — RESOLVED-AT-V44** (the single fix `213f9184` closed 7 catalog rows HANDOFF-111..117; removed from the v45.0+ register — see §9d.3).
2. HANDOFF-31 V-063 closes V-073 (HANDOFF-40) collaterally.
3. HANDOFF-36 V-069 closes V-070 (HANDOFF-37).
4. HANDOFF-38 V-071 closes V-080 (HANDOFF-42).
5. HANDOFF-20 V-043 closes V-045 (HANDOFF-21) + V-046 (HANDOFF-22) — the V-046 OZ-carveout fix lands in `contracts/`.
6. HANDOFF-23 V-047 closes V-048 (HANDOFF-24).
7. HANDOFF-47 V-089 closes V-091/V-095/V-098/V-101 (HANDOFF-49/53/56/59) — 5 rows.
8. HANDOFF-48 V-090 closes V-093/V-096/V-099/V-102 (HANDOFF-51/54/57/60) — 5 rows.
9. HANDOFF-50 V-092 closes V-104 (HANDOFF-62).
10. HANDOFF-46 V-088 closes V-094/V-097/V-100 (HANDOFF-52/55/58) — 4 rows.
11. HANDOFF-78 V-137 closes 5 governance rows (HANDOFF-85/87/89/91). HANDOFF-86 V-156 closes 3 wireVrf rows (HANDOFF-88/90).

Plus J-cluster co-located fan-out: HANDOFF-92..100 cover V-179.A..I writers at the same EOA entry points (HANDOFF-101..109 subsumed at same gate). Net: ~24 active-fix sub-phases for the 112 carried-forward HANDOFF anchors (the v43 ~25-sub-phase budget minus the now-closed V-184 PRIORITY-1 sub-phase).

#### §9d.6 — Carry-forward non-handoff items

Per `D-44N-FCITE-01` allowed-exception pattern: locked-decision IDs + descriptive labels only (no post-Phase-308 phase numbers).

- **`D-42N-MINTCLN-SCOPE-01`** — helper-extraction handoff for MINTCLN duplicate-logic (v42 carry).
- **`D-42N-EVT-BREAK-01`** — indexer-migration handoff for `TraitsGenerated` topic-hash break (off-chain, user-owned).
- **`D-40N-LBX02-OUT-01`** — LBX-02 fixture-coverage gap carry. Analytical worst-case continues load-bearing per `feedback_gas_worst_case.md`.
- **`D-40N-MINTBOOST-OUT-01`** — mint-boost path retention carry (`_queueTicketsScaled` + `_rollRemainder` + `rem` byte; deterministic dust accumulator; not RNG-driven).
- **`D-42N-RETRY-RNG-DOMAIN-SEP-01`** — domain-separation policy for retryLootboxRng entropy-correlation (Option A documentation-only ACCEPT_AS_DOCUMENTED default; Option B behavioral remediation requires user approval per `feedback_never_preapprove_contracts.md`). Default carry forward as documentation-only.
- **`D-42N-RETRY-RNG-SCOPE-DOC-01`** — docstring/scope-boundary observation; documentation-scope only.
- **`D-42N-RETRY-RNG-LAUNCH-FAQ-01`** — launch-comms FAQ entries; out-of-repo; user-owned communication.
- **Game-over hardening** — separate dedicated milestone scope (descriptive label; no locked-decision ID; reserved for a future game-over-surface milestone).
- **v43 FUZZ harness 3 missing edge-case functions** — cross-EOA Sybil within rngLock window + ERC721 receiver-callback re-entry on deity-pass mint + stETH yield accrual mid-window. DEFERRED to the v45.0+ FIX-MILESTONE per the v43 P302 LOG user disposition Item 5 verdict (b) DEFER.

---

*End of audit/FINDINGS-v44.0.md.*
