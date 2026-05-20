# Phase 308: Delta Audit + Findings Consolidation (TERMINAL) - Context

**Gathered:** 2026-05-19
**Status:** Ready for planning
**Posture:** v44.0 FIX-milestone TERMINAL. SOURCE-TREE FROZEN — zero `contracts/` + zero `test/` mutations during Phase 308. 2-commit sequential SHA orchestration pre-authorized per `D-44N-CLOSURE-PREAUTH-01` (locked at Phase 304 SPEC signoff).

<domain>
## Phase Boundary

TERMINAL phase shipping `audit/FINDINGS-v44.0.md` 9-section deliverable + closure-flip per AUDIT-01..09 + REG-01 + CLS-01..02 (12 primary requirements). Sections:

- **§1 + §2** — milestone header + scope statement (v44.0 sStonk per-day refactor; v43.0 closure HEAD `MILESTONE_V43_AT_HEAD_8111cfc5189f628b64b500c881f9995c3edf0ed2` as audit baseline)
- **§3.A** delta-surface table — Phase 305 USER-APPROVED contract commit `213f9184` + AGENT-COMMITTED test/audit/planning commits, **load-bearing depth** (~7-8 rows) per `D-308-DELTA-SURFACE-DEPTH-01`
- **§3.B** per-exempt-entry-point attestation matrix — 3 exempt entry points × per-participating-slot row; sStonk-specific row for `redemptionPeriods[day].roll` exempt writer = `resolveRedemptionPeriod`
- **§3.C** conservation re-proof — INV-01..13 each attested as proven by a specific TST-NN / EDGE-NN / fuzz-fn ID per `D-308-INV-COUNT-01` (13 INV reality, not ROADMAP's 12)
- **§3.D** V-184 disposition — explicit RESOLVED-AT-V44 attestation; HANDOFF-111..117 all closed; cross-reference to TST-04 + TST-05 + EDGE-07
- **§3.E** remaining v43 backlog reference — 135 anchors deferred to v45.0+ via v43.0 §9d handoff register; v44.0 does not consume them
- **§3.F** formal invariant attestation matrix **NEW for v44.0** — `(INV-NN, test_id, status)` rows × **13 invariants** per `D-308-INV-COUNT-01`; status enum = PROVEN / WAIVED-with-rationale / FAILING-blocks-closure
- **§4** adversarial-pass disposition — Phase 307 SWEEP unanimous-NEGATIVE outcome condensed to ~17 hypothesis rows (5 SWP + 5 augments + 7 beyond-charge) per `D-308-ADVERSARIAL-DISP-01`; cross-references `307-01-ADVERSARIAL-LOG.md` for full 72-row Disposition table
- **§5** LEAN regression REG-01 — v43.0 closure non-widening; every v43.0 audit-subject surface byte-identical at v44.0 close EXCEPT the Phase 301 `vm.skip(HANDOFF-111..117)` lines flipped to strict assertions (intended diff attested in §3.A)
- **§6** KI walkthrough — EXC-01..04 RE_VERIFIED-NEGATIVE-scope at v44 close; KNOWN-ISSUES.md UNMODIFIED per `D-44N-KI-01`
- **§7** prior-artifact cross-cites
- **§8** forward-cite closure — zero post-milestone references per `D-44N-FCITE-01` carry; pickup-pointers via locked-decision IDs only
- **§9** closure attestation — `7 of 7 SSTONK_VIOLATIONS RESOLVED_AT_V44; 13 of 13 INVARIANTS PROVEN; 20 of 20 EDGE_CASES TESTED; 0 NEW_FINDINGS; KNOWN_ISSUES_UNMODIFIED` per `D-308-INV-COUNT-01` (diverges from ROADMAP template's "12 / 18" counts; emits the Phase 306 actual coverage)
- **§9d** v45.0+ handoff register — 135 remaining v43 anchors per `D-43N-V44-HANDOFF-NN` excluding the 7 closed by v44.0 + 22 ADMA + 1 ADMA-ERRATUM

**Wave shape:** 2 AGENT-COMMITTED commits per CLS-01 + `D-44N-CLOSURE-01`:
- **Commit 1** ships `audit/FINDINGS-v44.0.md` with `<commit-1-sha>` placeholder + planner-private bundle
- **Commit 2** resolves `<commit-1-sha>` placeholder + propagates verbatim to 5 FINDINGS verbatim locations + 3 cross-doc targets + `chmod 444 audit/FINDINGS-v44.0.md` + atomic 5-doc closure flip (ROADMAP / STATE / MILESTONES / PROJECT / REQUIREMENTS)

Pre-authorized per `D-44N-CLOSURE-PREAUTH-01` — no user-pause at Commit 2.

</domain>

<decisions>
## Implementation Decisions

### Carried Forward (locked precedent — non-negotiable)

- **D-303-CLOSURE-01 (carry → `D-44N-CLOSURE-01`)** — 2-commit sequential SHA orchestration. Commit 1 = audit deliverable with `<commit-1-sha>` placeholder; Commit 2 = resolve placeholder + propagate verbatim + chmod 444 + atomic 5-doc closure flip.
- **D-44N-CLOSURE-PREAUTH-01** — user grants closure-flip authorization at Phase 304 SPEC signoff; eliminates Tier-1 ping at Commit 2. Phase 308 fires Commit 2 autonomously after Commit 1 SHA resolution.
- **D-44N-KI-01** — KNOWN-ISSUES.md UNMODIFIED at v44 close. EXC-01..04 RE_VERIFIED-NEGATIVE-scope (v44 audit subject is sStonk redemption refactor with zero affiliate-roll / AdvanceModule game-over-RNG-substitution interaction beyond sStonk-internal); §6 walkthrough enumerates each exception's NEGATIVE-scope justification without mutation.
- **D-44N-FCITE-01 (carry from `D-NN-FCITE-01`)** — zero forward-cite emission at v44 closure HEAD. §9d uses locked-decision IDs only (no "see Phase NN+M" references; `D-43N-V44-HANDOFF-NN` IDs which v45.0+ plan-phase resolves to its own phase numbering).
- **D-303-RESEARCH-AGENT-01 (carry)** — Plan-phase skips `gsd-phase-researcher` dispatch. TERMINAL deliverable shape locked by ROADMAP + REQUIREMENTS + v42 P297 + v43 P303 precedents; methodology is concentrated authoring work, not research.
- **5 FINDINGS verbatim locations + 3 cross-doc propagation targets** — locked per CLS-01. Phase 308 plan-time enumerates the 5 verbatim sites inside `audit/FINDINGS-v44.0.md` for `<commit-1-sha>` placeholder resolution + the 3 cross-doc targets (ROADMAP / STATE / MILESTONES + PROJECT + REQUIREMENTS atomic flip; precedent treats ROADMAP/STATE/MILESTONES as the 3 cross-doc; PROJECT + REQUIREMENTS are additional 2 in the "5-doc closure flip" framing).

### Phase 308 — New Decisions

#### D-308-INV-COUNT-01: §3.F + §3.C + §9 reflect Phase 306 actual coverage (13 INV / 20 EDGE)

- **D-308-INV-COUNT-01:** §3.F formal invariant attestation matrix enumerates **INV-01..13** (13 invariants) — not the ROADMAP-template-prescribed 12. §3.C conservation re-proof attests INV-01..13 each proven by a specific TST-NN / EDGE-NN / fuzz-fn ID. §9 closure verdict emits `7 of 7 SSTONK_VIOLATIONS RESOLVED_AT_V44; 13 of 13 INVARIANTS PROVEN; 20 of 20 EDGE_CASES TESTED; 0 NEW_FINDINGS; KNOWN_ISSUES_UNMODIFIED` — diverges from ROADMAP `12 / 18` template but reflects Phase 306 actual coverage.

  **Why:** Phase 305 IMPL added INV-13 as the emergent single-pool sentinel invariant (`D-305-SENTINEL-01` mechanizes the structural property that backs the V-184 closure). Phase 306 shipped `invariant_INV_13_SinglePoolPending` (`306-04-SUMMARY.md` line 130) PROVEN at deep × 256,000 calls. Phase 307 CHARGE already references `INV-01..13`. Phase 306 also extended the EDGE enumeration from 18 to 20 fuzz fns (EDGE-19..20 cover transfer-mid-pending + approve-mid-stall perturbations). The TERMINAL deliverable must attest reality, not a stale template count. Diverging from ROADMAP's verdict-template string is the lesser harm vs. silently dropping the emergent INV-13 + EDGE-19..20 coverage from the audit trail.

  **How to apply:** Plan Task authoring §3.F enumerates 13 rows; §3.C enumerates 13 conservation re-proof entries; §9 closure verdict string emits 13/13 + 20/20 verbatim. Plan-time grep-verifies the count against `test/invariant/RedemptionAccounting.t.sol` `invariant_*` fns + `test/fuzz/RedemptionEdgeCases.t.sol` `testFuzz_EDGE_*` fns. Add a one-line attestation row inside §3.F noting "INV count diverges from ROADMAP template (12 → 13) per `D-308-INV-COUNT-01`; emergent INV-13 from `D-305-SENTINEL-01` mechanized at Phase 306 Plan 01" so the audit trail captures the divergence rationale in-band. Same one-liner pattern for EDGE (18 → 20) inside §9 attestation.

#### D-308-ADVERSARIAL-DISP-01: §4 condensed disposition (~17 hypothesis rows)

- **D-308-ADVERSARIAL-DISP-01:** §4 adversarial-pass disposition condenses Phase 307 SWEEP's 72-row LOG into ~17 hypothesis rows: **5 SWP** (SWP-01..05 verbatim charges) + **5 v44-specific augments** (i)..(v) per `D-307-CHARGE-01` (1-slot DayPending packing + pendingResolveDay sentinel + gwei-snap precision + Phase 306 INV harness gap + Vault scope-expansion ACL) + **~7 beyond-charge rows** from `/economic-analyst` (MEV burn-ordering + vault flash-loan + sybil + late-entrant + whale-coordination + activity-score griefing + coinflip-drain).

  Each row columns: Hypothesis-ID | Source-skill | Verdict (NEGATIVE-VERIFIED / FINDING_CANDIDATE / SAFE_BY_DESIGN) | Severity tag | Cross-skill consensus (Tier-1 / Tier-2 / unanimous-NEGATIVE) | LOG cross-reference (`307-01-ADVERSARIAL-LOG.md#H2-section`).

  Skeptic-Filter results: one summary line ("0 discards across per-skill self-filter + orchestrator integration-time re-application; dual-gate filter applied per `D-307-SKEPTIC-FILTER-01`") + cross-reference to the LOG's Skeptic-Filter Discarded table (which is empty for v44 because no `FINDING_CANDIDATE` inputs existed across all 3 skills).

  **Why:** v41 P284 + v43 P303 §4 used condensed format; verbatim 72-row transcription is redundant with `307-01-ADVERSARIAL-LOG.md` which is AGENT-COMMITTED at `.planning/phases/307-*/`. Audit-trail completeness is preserved via the LOG cross-reference column. Condensed format is the readable summary; the LOG is the authoritative detail.

  **How to apply:** Plan Task authoring §4 enumerates the 17 hypothesis rows. Plan-time reads `307-01-ADVERSARIAL-LOG.md` Disposition section + per-skill MD §[skeptic-filter] frontmatter + Severity-Downgrade Rationale table to extract the per-hypothesis verdict + consensus state + LOG anchor. Severity tags from `D-307-SKEPTIC-FILTER-01` enum {CATASTROPHE, HIGH, MEDIUM, LOW, N-A}; v44 outcome is unanimous-NEGATIVE so most rows tag N-A.

#### D-308-DELTA-SURFACE-DEPTH-01: §3.A load-bearing depth (~7-8 rows)

- **D-308-DELTA-SURFACE-DEPTH-01:** §3.A delta-surface table aggregates the v44.0 commit envelope into ~7-8 load-bearing rows, not per-commit verbatim. Row enumeration:

  1. **Phase 304 SPEC bundle** — aggregated planning + SPEC commits (e.g., `6edc3967` + `315280b0` + `971688ba` SPEC §1/§2/§3 Plan 01/02/03); classification AGENT-COMMITTED-planning; delta-class PLANNING.
  2. **Phase 305 USER-APPROVED contract commit** — `213f9184 feat(305-01): v44.0 sStonk per-day redemption refactor — 1-slot DayPending + INV-13 sentinel`; classification USER-APPROVED; delta-class CONTRACT.
  3. **Phase 305 planning bundle** — `c6f7045b` pre-patch grep-verification manifest + `47ab0b3f` plan-complete summary; classification AGENT-COMMITTED-planning; delta-class PLANNING.
  4. **Phase 306 Plan 01 (invariant harness)** — `de75f620` + planning; classification AGENT-COMMITTED-test; delta-class TEST.
  5. **Phase 306 Plans 02..03 (EDGE-01..20 fuzz)** — `333c803f` + `3143ea9c` + `d24a2487` + planning; classification AGENT-COMMITTED-test; delta-class TEST.
  6. **Phase 306 Plan 04 (Phase 301 vm.skip flip + REG-01)** — `b102bc0f test(306-04): flip V-184 / HANDOFF-111 vm.skip to strict assertion`; classification AGENT-COMMITTED-test; delta-class TEST; **REG-01 anchor** (this is the only intended `test/` diff vs v43.0 baseline per REG-01).
  7. **Phase 306 Plan 05 (gas regression bench)** — `e0f7d77e test(306-05): gas regression bench — TST-06 closure`; classification AGENT-COMMITTED-test; delta-class TEST.
  8. **Phase 307 SWEEP LOG bundle** — Phase 307 docs commits (`b3fcee2c` + `a83ebc4c` + `3dc7cafd` + `5448cd5d` + `1352be27` + `e58b03b9` + `c7ef7219`); classification AGENT-COMMITTED-audit; delta-class AUDIT.

  Each row columns: Row-ID | Phase | Commit-SHA-range | Subject summary | Classification | Delta-class | Cross-reference. The single USER-APPROVED contract commit (`213f9184`) gets its own row (row 2) so the contract diff is explicitly enumerated.

  **Why:** v43 P303 §3.A used phase-aggregated rows (audit-only posture); v44 reuses the same aggregation pattern but inserts row 2 for the USER-APPROVED contract diff which v43 lacked. Per-commit verbatim (~28 rows) is excessive — `git log` is the authoritative per-commit trail; §3.A is the audit-deliverable summary. Hybrid drill-down was rejected because the planning-doc commits don't carry audit-load-bearing weight; their aggregation into a single row per phase is appropriate.

  **How to apply:** Plan Task authoring §3.A enumerates these 8 rows verbatim. Plan-time runs `git log --oneline 5448cd5d..c7ef7219` (or equivalent commit-SHA range queries per phase) to extract the per-row SHA list; row "Commit-SHA-range" field captures the first..last SHA pair (or single SHA for single-commit rows). Plan-time grep-verifies the contract commit identity is exactly `213f9184` against `git log --all --oneline | grep "feat(305-01)"`.

#### D-308-TASK-SPLIT-01: 1 plan / 13 tasks (mirror D-303-TASK-SPLIT-01)

- **D-308-TASK-SPLIT-01:** Single plan `308-01-PLAN.md` with 13 tasks mirroring D-303-TASK-SPLIT-01:

  1. Author §3.A delta-surface table (8 rows per `D-308-DELTA-SURFACE-DEPTH-01`).
  2. Author §3.B per-exempt-entry-point attestation matrix (3 exempt entry points × per-participating-slot rows; sStonk-specific row for `redemptionPeriods[day].roll` exempt writer = `resolveRedemptionPeriod`).
  3. Author §3.C conservation re-proof (INV-01..13 each attested by specific TST-NN / EDGE-NN / fuzz-fn ID).
  4. Author §3.D V-184 disposition (RESOLVED-AT-V44 + HANDOFF-111..117 closure + TST-04 / TST-05 / EDGE-07 cross-refs).
  5. Author §3.E v43 backlog reference (135 anchors deferred to v45.0+).
  6. Author §3.F formal invariant attestation matrix (13 rows per `D-308-INV-COUNT-01`).
  7. Author §4 adversarial-pass disposition (~17 condensed rows per `D-308-ADVERSARIAL-DISP-01`).
  8. Author §5 LEAN regression REG-01 (v43.0 closure non-widening; Phase 301 vm.skip flip is the only intended `test/` diff, attested in §3.A row 6).
  9. Author §6 KI walkthrough (EXC-01..04 RE_VERIFIED-NEGATIVE-scope; KNOWN-ISSUES.md UNMODIFIED).
  10. Author §7 prior-artifact cross-cites + §8 forward-cite closure + §9 closure attestation (`7 of 7 SSTONK_VIOLATIONS RESOLVED_AT_V44; 13 of 13 INVARIANTS PROVEN; 20 of 20 EDGE_CASES TESTED; 0 NEW_FINDINGS; KNOWN_ISSUES_UNMODIFIED`) + §9d v45.0+ handoff register (135 remaining anchors).
  11. Commit 1 — `git commit` ships `audit/FINDINGS-v44.0.md` with `<commit-1-sha>` placeholder + planner-private bundle.
  12. Commit 2 — resolve `<commit-1-sha>` placeholder + propagate verbatim to 5 FINDINGS locations + 3 cross-doc targets + `chmod 444 audit/FINDINGS-v44.0.md` + atomic 5-doc closure flip (ROADMAP / STATE / MILESTONES / PROJECT / REQUIREMENTS) + `git commit`.
  13. Update STATE.md / MILESTONES.md / PROJECT.md / ROADMAP.md / REQUIREMENTS.md atomic flip rolls into Commit 2 (the 5-doc closure-flip IS the state-update). AGENT-COMMIT bundle for Phase 308 closure.

  **Why:** D-303-TASK-SPLIT-01 (13 tasks) is the proven template; v44 has the same 9-section deliverable shape + 2-commit closure shape. Single plan keeps the artifact bundle atomic. Plan→deliverable→closure flows in one continuous task chain; main-context execution per D-303-EXEC-SHAPE-01 carry.

  **How to apply:** Planner authors `308-01-PLAN.md` with these 13 tasks. Sub-task structure inside each authoring task per planner discretion (each §-author task may have substeps: read prior-phase artifacts → extract data → author section → grep-verify citations). Commit 2's atomic 5-doc closure flip MUST run as a single `git commit` (5 files staged together) per CLS-01 atomicity.

### Claude's Discretion (planner & executor latitude)

- **Per-§ sub-agent decomposition** — D-303-EXEC-SHAPE-01 carries "main-context end-to-end with per-§ sub-agent dispatch possible at plan-phase discretion if individual sections are heavy". Phase 308 sections are concentrated authoring; main-context is the default. If §3.A or §4 cross-referencing becomes burdensome, planner may dispatch a sub-agent for that section.
- **Row ordering inside §3.F** — INV-NN sequential (1..13) is the default. Planner may sort by status (PROVEN first, WAIVED next, FAILING last) if any non-PROVEN rows surface — but per Phase 306 outcome, all 13 are PROVEN, so sequential ordering is the expected emission.
- **§3.C vs §3.F overlap** — §3.C is conservation re-proof (textual: which fn proves which property, with prose); §3.F is the structured matrix (tabular: `(INV-NN, test_id, status)` rows). Planner ensures the two are consistent — §3.C is the narrative form, §3.F is the audit-trail tabular form. Same 13 INV underlie both; the per-INV test_id MUST match across §3.C + §3.F.
- **§3.A row aggregation boundaries** — the 8 rows enumerated in `D-308-DELTA-SURFACE-DEPTH-01` are the load-bearing default. Planner may split a row into two if the aggregation obscures a load-bearing distinction (e.g., split Phase 306 Plan 04 from Plan 05 if the gas-regression bench warrants its own row separate from the vm.skip flip).
- **5 FINDINGS verbatim locations enumeration** — Phase 308 plan-time identifies the 5 sites inside `audit/FINDINGS-v44.0.md` where `<commit-1-sha>` placeholder appears (typical pattern: §1 header + §9 closure attestation + §9d handoff anchor + §3.A row 2 sub-text + one more per v43 P303 precedent). Plan-time enumerates exactly; v43 P303 had 5 verbatim sites; mirror that pattern.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents (planner, executor) MUST read these before planning or implementing.**

### Phase 308 Anchors
- `.planning/ROADMAP.md` §"Phase 308: Delta Audit + Findings Consolidation (TERMINAL)" — Goal statement + 5 success criteria + 9-section deliverable shape + 2-commit sequential SHA orchestration locked per `D-44N-CLOSURE-01` + pre-authorization per `D-44N-CLOSURE-PREAUTH-01`.
- `.planning/REQUIREMENTS.md` §"AUDIT-01..09 + REG-01 + CLS-01..02" — verbatim 12 primary requirements.
- `.planning/PROJECT.md` §"Current Milestone: v44.0" — milestone goal + 12 non-negotiable acceptance criteria + audit baseline v43.0 closure HEAD.
- `.planning/STATE.md` — current focus (Phase 308 TERMINAL; Phase 307 SWEEP closed at `c7ef7219`).

### Load-Bearing Upstream Phase Artifacts (Phase 304-307)
- `.planning/phases/304-spec-invariant-model-spec/304-SPEC.md` — Phase 304 SPEC (960 lines, 35 LOCKED requirements: INV-01..12 + SPEC-01..05 + EDGE-01..18). **§3.F + §3.C MUST cross-reference this for canonical INV definitions.**
- `.planning/phases/305-implementation-impl/305-CONTEXT.md` — Phase 305 IMPL CONTEXT.
- `.planning/phases/305-implementation-impl/305-01-SUMMARY.md` — Phase 305 IMPL summary; v44 emergent surfaces: `D-305-SENTINEL-01` (`pendingResolveDay` sentinel + INV-13 + PriorDayUnresolved revert); `D-305-STRUCT-TIGHTEN-01` (1-slot DayPending); `D-305-GWEI-SNAP-01`; `D-305-DUST-FLOOR-01`; `D-305-DAYTORESOLVE-01`.
- `.planning/phases/306-test-tst/306-01-SUMMARY.md` — Phase 306 Plan 01 (Foundry invariant harness; INV-01..13 PROVEN at deep × 256,000 calls).
- `.planning/phases/306-test-tst/306-02-SUMMARY.md` — Phase 306 Plan 02 (EDGE-01..20 fuzz suite PROVEN at 10k runs each).
- `.planning/phases/306-test-tst/306-03-SUMMARY.md` — Phase 306 Plan 03 (per-function fuzz suite — 8 testFuzz_* fns).
- `.planning/phases/306-test-tst/306-04-SUMMARY.md` — Phase 306 Plan 04 (V-184 vm.skip flip + REG-01 strict-byte-identity attestation).
- `.planning/phases/306-test-tst/306-05-SUMMARY.md` — Phase 306 Plan 05 (TST-06 gas regression bench).
- `.planning/phases/306-test-tst/306-VERIFICATION.md` — Phase 306 verification (13 INV + 20 EDGE + 8 per-fn fuzz + V-184 strict-byte-identity + 2 gas regression assertions PROVEN).
- `.planning/phases/307-adversarial-sweep-sweep/307-CONTEXT.md` — Phase 307 SWEEP CONTEXT (D-307-* decision set).
- `.planning/phases/307-adversarial-sweep-sweep/307-ADVERSARIAL-CHARGE.md` — Phase 307 CHARGE (SWP-01..05 + 5 v44-specific augments + grep-verified file:line evidence anchors).
- `.planning/phases/307-adversarial-sweep-sweep/307-ADVERSARIAL-CONTRACT-AUDITOR.md` — `/contract-auditor` per-skill MD (22 NEGATIVE-VERIFIED).
- `.planning/phases/307-adversarial-sweep-sweep/307-ADVERSARIAL-ZERO-DAY-HUNTER.md` — `/zero-day-hunter` per-skill MD (22 NEGATIVE-VERIFIED).
- `.planning/phases/307-adversarial-sweep-sweep/307-ADVERSARIAL-ECONOMIC-ANALYST.md` — `/economic-analyst` per-skill MD (25 NEGATIVE-VERIFIED + 3 SAFE_BY_DESIGN; 7 beyond-charge rows).
- `.planning/phases/307-adversarial-sweep-sweep/307-01-ADVERSARIAL-LOG.md` — integrated 3-H2-section LOG + Skeptic-Filter Discarded table + Disposition table + Severity-Downgrade Rationale table; **§4 condensed disposition cross-references this for full 72-row detail**.
- `.planning/phases/307-adversarial-sweep-sweep/307-01-SUMMARY.md` — Phase 307 SUMMARY (unanimous-NEGATIVE outcome; Task 6 elevation gate skipped).

### Test Artifacts Under §3.C + §3.F Attestation
- `test/invariant/RedemptionAccounting.t.sol` — 13 `invariant_INV_NN_*` fns; PROVEN at FOUNDRY_PROFILE=deep × 256,000 calls. **§3.C + §3.F test_id source.**
- `test/fuzz/RedemptionEdgeCases.t.sol` — 20 `testFuzz_EDGE_NN_*` fns; PROVEN at 10k runs each.
- `test/fuzz/StakedStonkRedemption.t.sol` — 8 per-function fuzz tests.
- `test/fuzz/RngLockDeterminism.t.sol:1278` — `vm.skip(HANDOFF-111..117)` flipped to strict byte-identity assertion (TST-05; REG-01 anchor; **the only intended `test/` diff vs v43.0 baseline**).
- `test/fuzz/RedemptionGas.t.sol` — 2 gas regression assertions (burn ≤ +5% v43; claim ≤ +0% v43; TST-06).

### Contracts Under §3.B Per-Exempt-Entry-Point Attestation
- `contracts/StakedDegenerusStonk.sol` — Primary v44 audit subject; `:636` `resolveRedemptionPeriod` writes `redemptionPeriods[day].roll` (the new sStonk-specific row in §3.B).
- `contracts/modules/DegenerusGameAdvanceModule.sol` — 3 call sites (`:1228, :1294, :1327`) into `resolveRedemptionPeriod`; `advanceGame()` reachable from each.
- `contracts/interfaces/IStakedDegenerusStonk.sol` — interface signatures matching v44.0 IMPL surface.

### v43 Phase 303 TERMINAL Precedent (load-bearing for shape inheritance)
- `audit/FINDINGS-v43.0.md` — v43 9-section deliverable shape (read-only at v43 closure HEAD `8111cfc5`, chmod 444). Direct template inheritance with v44-specific adjustments (FIX-milestone verdict math, §3.D V-184 disposition, §3.F NEW formal invariant attestation matrix).
- `.planning/milestones/v43.0-phases/303-delta-audit-findings-consolidation-terminal/303-CONTEXT.md` — D-303-CLOSURE-01 + D-303-VERDICT-01 + D-303-KI-01 + D-303-V44-HANDOFF-REGISTER-01 + D-303-FCITE-01 + D-303-EXEC-SHAPE-01 + D-303-RESEARCH-AGENT-01 + D-303-TASK-SPLIT-01 — load-bearing precedent for shape + decision inheritance.
- `.planning/milestones/v42.0-phases/297-delta-audit-findings-consolidation-terminal/297-CONTEXT.md` — D-297-CLOSURE-01 + D-297-VERDICT-01 + D-297-KI-01 + D-297-DEFER-01 + D-297-FCITE-01 — upstream of D-303-*.
- `.planning/milestones/v41.0-phases/284-delta-audit-findings-consolidation-terminal/284-CONTEXT.md` — D-284-CLOSURE-01 — original 2-commit sequential SHA pattern.
- `audit/FINDINGS-v42.0.md` + `audit/FINDINGS-v41.0.md` — prior multi-finding milestone deliverable shapes (FIX-milestone verdict math precedent: `3 of 3 F-41-NN RESOLVED_AT_V41`).

### Audit Baseline + Closure Signal Chain
- v43.0 audit baseline HEAD `MILESTONE_V43_AT_HEAD_8111cfc5189f628b64b500c881f9995c3edf0ed2`
- v44.0 closure HEAD `MILESTONE_V44_AT_HEAD_<commit-1-sha>` — resolved at Phase 308 Commit 1 per `D-44N-CLOSURE-01`

### v43.0 FINDINGS Cross-Citations (for §3.D + §3.E + §9d)
- `audit/FINDINGS-v43.0.md` §9d — handoff register (142 anchors at v43 close; v44 consumes HANDOFF-111..117 = 7 of them; §3.E + §9d reference the remaining 135 = 119 D-43N-V44-HANDOFF-NN + 22 D-43N-V44-ADMA-NN + 1 D-43N-V44-ADMA-ERRATUM-01).
- `.planning/RNGLOCK-FIXREC.md` §103 — V-184 mechanic + game-theory walk (the original CATASTROPHE the v44 refactor closes structurally). **§3.D V-184 disposition cross-references this for the pre-fix mechanic + the RESOLVED-AT-V44 attestation.**
- `audit/FINDINGS-v43.0.md` §9d "Deferred to Future Milestones" — descriptive carry labels per `D-297-DEFER-01` lineage (preserve in §9d alongside the locked-decision-ID handoff register).

### Memory / Feedback Governing This Phase
- `feedback_no_history_in_comments.md` — TERMINAL deliverable describes what IS at v44 closure; no "this changed from v43" history prose. Cross-references via locked-decision IDs are anchors, not history.
- `feedback_frozen_contracts_no_future_proofing.md` — TERMINAL deliverable does not propose future-extensibility scaffolding; §9d handoff register is the explicit out-of-scope mechanism, not future-proofing prose.
- `feedback_skip_research_test_phases.md` — D-303-RESEARCH-AGENT-01 carry: skip `gsd-phase-researcher` dispatch for Phase 308.
- `feedback_verify_call_graph_against_source.md` — plan-time grep-verifies every cited file:line + commit SHA + INV-NN / EDGE-NN / TST-NN test_id reference against source before authoring. No "by construction" or "by inference" claims.
- `feedback_skeptic_pass_before_catastrophe.md` — Phase 307 SWEEP already operationalized; Phase 308 §4 summarizes the LOG outcome (unanimous-NEGATIVE; 0 discards) but does NOT re-run the skeptic filter. Cross-reference the LOG for the per-row provenance.

### Skill Source Definitions (informational; Phase 308 does NOT dispatch sub-agent skills)
- None — Phase 308 is concentrated TERMINAL authoring; main-context end-to-end per D-303-EXEC-SHAPE-01 carry.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- **v43 P303 9-section deliverable template** — direct shape inheritance; substitute v44 audit subjects (sStonk per-day refactor + INV-13 sentinel) for v43 audit subjects (rngLock determinism + per-VIOLATION FIXREC/ADMA roll-ups); add §3.D V-184 disposition + §3.F NEW formal invariant attestation matrix as v44-specific sections.
- **2-commit sequential SHA closure-flip pattern** — Phase 303 + Phase 297 + Phase 284 + Phase 280 + Phase 274 + Phase 271 + Phase 264 + Phase 257 + Phase 246 precedent (9-milestone lineage).
- **`<commit-1-sha>` placeholder + verbatim propagation pattern** — Phase 303 + Phase 297 + Phase 284 exact mechanism; Phase 308 plan-time enumerates the 5 verbatim sites inside `audit/FINDINGS-v44.0.md` + 3 cross-doc targets.
- **`chmod 444` on FINDINGS-vNN.md at closure** — preserves audit-deliverable immutability post-flip.

### Established Patterns
- **AGENT-COMMITTED terminal-phase commits** — 9-milestone precedent (v33..v43); v44 Phase 308 is the 10th.
- **FIX-milestone verdict math** — `N of N <CATEGORY>_VIOLATIONS RESOLVED_AT_V<NN>` (v41 P284 + v42 P297 precedent; v44 verdict tag `SSTONK_VIOLATIONS` per ROADMAP §9 template).
- **§3.F formal invariant attestation matrix** — first emission for v44.0; no prior precedent (v43 P303 was audit-only; no invariants proven, no §3.F). Phase 308 establishes the pattern for future FIX-milestone TERMINALs (v45.0+ if/when invariant-based closure becomes the standard).
- **Pre-authorized closure-flip** — `D-43N-CLOSURE-PREAUTH-01` precedent; `D-44N-CLOSURE-PREAUTH-01` carry. Phase 308 fires Commit 2 autonomously.

### Integration Points
- **Phase 304-307 → Phase 308**: every prior v44.0 phase produces an artifact consumed by a specific §N section of `audit/FINDINGS-v44.0.md`. Phase 304 SPEC → §3.C + §3.F INV/EDGE anchors; Phase 305 IMPL → §3.A row 2 contract commit + §3.B sStonk-specific row + §3.D V-184 structural-close attestation; Phase 306 TST → §3.C + §3.F test_id evidence + §5 REG-01 vm.skip flip + §3.A row 6; Phase 307 SWEEP → §4 disposition condensed input.
- **Phase 308 → v45.0+**: §9d handoff register lists 135 remaining v43 anchors verbatim (119 `D-43N-V44-HANDOFF-NN` excluding HANDOFF-111..117 + 22 `D-43N-V44-ADMA-NN` + 1 `D-43N-V44-ADMA-ERRATUM-01`). v45.0+ plan-phase reads this register as primary input.
- **Phase 308 → external audit**: `audit/FINDINGS-v44.0.md` (chmod 444 at closure) is the consumable deliverable for downstream auditors (C4A wardens; external review). The 9-section shape + closure verdict format + handoff register layout are stable across the v33..v44 lineage; external auditors learn the format once.

</code_context>

<specifics>
## Specific Ideas

- **§3.F NEW for v44.0** — first formal invariant attestation matrix; precedent establishes `(INV-NN, test_id, status)` row format with status enum {PROVEN, WAIVED-with-rationale, FAILING-blocks-closure}. v44 outcome: all 13 PROVEN, no waivers, no failures.
- **§3.A row 6 (Phase 306 Plan 04)** is the REG-01 anchor — the vm.skip flip is the only intended `test/` diff vs v43.0 baseline; §5 REG-01 attestation explicitly cross-references this row.
- **§3.D V-184 disposition** — explicit RESOLVED-AT-V44 with cross-references to TST-04 (`test/fuzz/RedemptionEdgeCases.t.sol` EDGE-07 testFuzz fn) + TST-05 (`test/fuzz/RngLockDeterminism.t.sol:1278` strict-byte-identity assertion) + EDGE-07 (the headline V-184 fuzz scenario). The V-184 closure is structural (per-day keying makes the overwrite primitive unreachable) + mechanized (INV-13 single-pool invariant PROVEN at 256k calls).
- **Diverging from ROADMAP verdict template (12 → 13 INV; 18 → 20 EDGE)** is in-band documented per `D-308-INV-COUNT-01`. Audit trail captures the divergence rationale; future readers see "Phase 305 added INV-13 emergent; Phase 306 extended EDGE to 20" without having to reconstruct from milestone-level lineage.
- **Pre-authorized closure orchestration** — `D-44N-CLOSURE-PREAUTH-01` eliminates the user-checkpoint ping at Commit 2; locked at Phase 304 SPEC signoff; Phase 308 fires Commit 2 autonomously after Commit 1 SHA resolution.

</specifics>

<deferred>
## Deferred Ideas

- **MILESTONE-AUDIT.md authoring** — post-closure-flip housekeeping; Phase 308 task or separate `/gsd:complete-milestone` invocation per `D-303-DEFER-01` precedent.
- **v45.0 plan-phase invocation** — explicitly OUT of v44 scope; v45 starts after v44 closure-flip lands. The 135-anchor handoff register at §9d is the v45.0+ primary input but Phase 308 does not consume it.
- **Cross-milestone adversarial RE-PASS (re-run v43 SWEEP against v44 surfaces)** — Phase 308 §5 REG-01 non-widening attestation + §6 KI walkthrough already cover v43-surface integrity; explicit re-run not needed.
- **Direct `contracts/*.sol` / `test/*.sol` mutations during Phase 308** — REJECTED. Phase 308 is SOURCE-TREE FROZEN per ROADMAP success criterion #5 (`git diff HEAD~2 HEAD -- contracts/ test/` MUST return no output across both Phase 308 commits).
- **Per-commit verbatim §3.A** — REJECTED per `D-308-DELTA-SURFACE-DEPTH-01`; load-bearing aggregation is the chosen depth.
- **Verbatim 72-row §4 disposition** — REJECTED per `D-308-ADVERSARIAL-DISP-01`; condensed format with LOG cross-references is the chosen format.
- **Sticking to ROADMAP's 12 INV / 18 EDGE verdict counts** — REJECTED per `D-308-INV-COUNT-01`; attest Phase 306 actual coverage.
- **§3.F WAIVED or FAILING rows** — N/A per Phase 306 outcome (all 13 INV PROVEN; no waivers; no failures). If a future v45.0+ TERMINAL emits non-PROVEN status, the planner re-evaluates ordering + closure-block semantics at that time.
- **Re-pinging user at Commit 2** — REJECTED per `D-44N-CLOSURE-PREAUTH-01`; pre-authorization holds.

</deferred>

---

*Phase: 308-Delta-Audit-Findings-Consolidation-TERMINAL*
*Context gathered: 2026-05-19*
