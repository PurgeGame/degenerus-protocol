# Phase 246: Findings Consolidation + Lean Regression Appendix — Context

**Gathered:** 2026-04-24
**Status:** Ready for planning
**Mode:** Interactive gray-area selection (user selected 2 of 4 areas — Plan Split topology + REG-02 SUPERSEDED sweep scope; REG-01 touched-by-deltas criteria + FIND-01 zero-findings deliverable shape auto-decided per Claude's Discretion with v30 Phase 242 precedent)

<domain>
## Phase Boundary

Publish `audit/FINDINGS-v31.0.md` as the v31.0 milestone-closure deliverable at HEAD `cc68bfc7`, mirroring the v29/v30 shape (executive summary / per-phase sections / F-31-NN finding blocks / regression appendix / FIND-03 KI gating walk + Non-Promotion Ledger / milestone-closure attestation). Conditionally update `KNOWN-ISSUES.md` only if the D-09 3-predicate gating produces ≥1 promoted candidate (default path is UNMODIFIED per D-16 carry).

5 requirements across 2 buckets:

- **FIND-01..FIND-03** (3 REQs) — Findings consolidation:
  - FIND-01 single canonical milestone deliverable `audit/FINDINGS-v31.0.md` with executive summary + per-phase sections (243/244/245) + F-31-NN finding blocks
  - FIND-02 every finding classified under D-08 5-bucket severity rubric `{CRITICAL, HIGH, MEDIUM, LOW, INFO}`
  - FIND-03 `KNOWN-ISSUES.md` updated if any candidate passes D-09 3-predicate gating (accepted-design + non-exploitable + sticky); UNMODIFIED otherwise

- **REG-01..REG-02** (2 REQs) — Lean regression appendix:
  - REG-01 spot-check regression — re-verify any v30.0 F-30-NNN finding directly touched by the 5 deltas; re-verify F-29-04 at HEAD `cc68bfc7`
  - REG-02 document any prior finding superseded by the new code (e.g., sDGNRS redemption protection may resolve a prior orphan-redemption edge case)

**Zero-state hand-off from Phase 245 (per `audit/v31-245-SDR-GOE.md` §5):**
- Phase 245 emitted 0 finding candidates across all 14 REQs (SDR-01..08 + GOE-01..06; all SAFE floor severity)
- FIND-01 finding-pool is empty (zero F-31-NN IDs to assign)
- FIND-02 has nothing to reclassify (zero candidates pre-classified by Phase 245)
- FIND-03 KI delta is zero (EXC-02 + EXC-03 envelopes RE_VERIFIED_AT_HEAD `cc68bfc7` without widening; no new exception added; no existing exception reclassified)
- Phase 244 also emitted 0 finding candidates (87 V-rows across 19 REQs all SAFE floor; 7 INFO observations were closed in-phase, not promoted to F-31-NN candidates)

**Scope source:** `audit/v31-243-DELTA-SURFACE.md` (FINAL READ-only) + `audit/v31-244-PER-COMMIT-AUDIT.md` (FINAL READ-only) + `audit/v31-245-SDR-GOE.md` (FINAL READ-only). All three upstream files are READ-only per D-21 carry; Phase 246 cites V-rows / X-rows / S-rows / Pre-Flag bullets as evidence but never edits the source files.

**Not in Phase 246:** Per-commit verdict generation (Phase 244 territory; FINAL at cc68bfc7); SDR/GOE deep sub-audit (Phase 245 territory; FINAL at cc68bfc7); delta-surface catalog (Phase 243 territory; FINAL at cc68bfc7); full v30.0 31-row regression sweep (out of scope per ROADMAP — replaced by REG-01 LEAN spot-check).

</domain>

<decisions>
## Implementation Decisions

### Plan Split & Topology (Gray Area 1 — user-selected)

- **D-01 (1 plan — single consolidation):** Mirrors v30 Phase 242 single-plan precedent (`audit/FINDINGS-v30.0.md` was authored under `phase: 242, plan: 01`). 5 REQs + zero-finding-candidate input + LEAN regression scope means the total work fits comfortably in one plan. Plan filename: `246-01-PLAN.md`.

- **D-02 (6 tasks — 1 per major artifact section):** Highest reviewability per atomic commit. Task layout maps 1:1 to `audit/FINDINGS-v31.0.md` section structure:
  1. **Task 1** — Setup + frontmatter + executive summary + severity counts (CRITICAL 0 / HIGH 0 / MEDIUM 0 / LOW 0 / INFO 0) + D-08 5-bucket severity rubric reference table + KI gating rubric reference
  2. **Task 2** — Per-phase sections (Phase 243 condensed summary + Phase 244 condensed summary + Phase 245 condensed summary; cross-cite source artifacts `audit/v31-243-DELTA-SURFACE.md` / `audit/v31-244-PER-COMMIT-AUDIT.md` / `audit/v31-245-SDR-GOE.md` plus working file appendices)
  3. **Task 3** — F-31-NN finding block (zero-attestation prose: one paragraph stating `audit/v31-244-PER-COMMIT-AUDIT.md` produced 87 V-rows all SAFE / `audit/v31-245-SDR-GOE.md` produced 55 V-rows all SAFE; therefore F-31-NN pool is empty; cross-cite to Phase 245 §5 zero-state subsection)
  4. **Task 4** — Regression appendix (REG-01 LEAN spot-check + REG-02 SUPERSEDED sweep — see D-08..D-12 below for methodology)
  5. **Task 5** — FIND-03 KI gating walk + Non-Promotion Ledger (zero-row variant — see D-13..D-15)
  6. **Task 6** — Milestone-closure attestation (6-point per D-18) + READ-only frontmatter flip + plan-close SUMMARY commit

- **D-03 (direct write to `audit/FINDINGS-v31.0.md`, no working file intermediary):** Matches v30 Phase 242 pattern. Each task writes its assigned section directly into the published artifact across atomic commits. No `audit/v31-246-WORK.md` scratch file; no consolidation step needed because there's nothing to consolidate (single-plan + single-deliverable).

- **D-04 (per-task atomic commits + READ-only flip on Task 6 final commit):** 6 commits within the plan (one per task), plus a final plan-close SUMMARY commit on Task 6. Frontmatter `status: FINAL — READ-ONLY` flipped on Task 6. Matches Phase 244-04 / 245-02 multi-commit-within-single-plan pattern; each commit independently reviewable.

### Severity Classification (carry from v30 D-08; no re-litigation)

- **D-05 (D-08 5-bucket severity rubric, verbatim from v30 Phase 242):** Severity calibration `{CRITICAL, HIGH, MEDIUM, LOW, INFO}` mapped via player-reachability × value-extraction × determinism-break frame inherited from v30 D-08:
  - CRITICAL — Player-reachable, material protocol value extraction, no mitigation at HEAD
  - HIGH — Player-reachable, bounded value extraction OR no extraction but hard determinism violation
  - MEDIUM — Player-reachable, no value extraction, observable behavioral asymmetry
  - LOW — Player-reachable theoretically but not practically (gas economics / timing / coordination cost makes exploit non-viable)
  - INFO — Not player-reachable, OR documented design decision, OR observation only (naming inconsistency, dead code, gas optimization, doc drift)
- The rubric reference table is reproduced verbatim in Task 1 of `audit/FINDINGS-v31.0.md`. Phase 246 does NOT re-litigate the rubric — it applies it.
- Phase 245's zero finding-candidate output means FIND-02 has nothing to classify; the rubric reference table is published for completeness + Phase 246-future-reader benefit, not for active classification work.

### KI Gating (carry from v30 D-09 + D-16; no re-litigation)

- **D-06 (3-predicate KI gating, verbatim from v30 Phase 242 D-09):** A finding-candidate qualifies for `KNOWN-ISSUES.md` promotion only if ALL three predicates hold:
  1. **Accepted-design** — the behavior is intentional, documented, or load-bearing for the protocol's design (not an oversight or accident)
  2. **Non-exploitable** — no player-reachable path extracts protocol value or breaks determinism
  3. **Sticky** — the design choice persists across foreseeable future code revisions (i.e., not a transient state that next milestone will remove)
- All three must be TRUE for promotion. ANY false ⇒ Non-Promotion Ledger entry with the failing predicate identified.

- **D-07 (D-16 default UNMODIFIED path, verbatim from v30 Phase 242 D-16):** `KNOWN-ISSUES.md` is **NOT** modified by Phase 246 unless ≥1 candidate clears all 3 predicates. Default path = UNMODIFIED. With Phase 245 zero-finding-candidate input + Phase 244 zero-finding-candidate input, the expected outcome is UNMODIFIED.
- KI envelope re-verifications (EXC-02 + EXC-03 RE_VERIFIED_AT_HEAD `cc68bfc7` from Phase 245 SDR-08-V01 + GOE-01-V01 + GOE-04-V02) are NOT KI promotions — they confirm existing entries' acceptance envelopes did not widen. They are documented in Task 5's KI gating walk as "envelope-non-widening attestations," not as new KI rows.

### REG-01 Touched-By-Deltas Criteria (Gray Area 3 — auto-decided per Claude's Discretion; planner refines)

- **D-08 (inclusion rule — domain-cite + delta-surface mapping):** A prior finding (v25.0 / v27.0 / v28.0 / v29.0 / v30.0) is "directly touched by deltas" iff its evidence cites a consumer / path / site / state-var / event / interface method that is itself touched by ≥1 of the 5 v31.0 deltas (`ced654df` JackpotTicketWin event scaling / `16597cac` rngunlock fix / `6b3f4f3c` quests recycled-ETH / `771893d1` gameover liveness-gate + sDGNRS redemption protection / `cc68bfc7` BAF flip-gate addendum). The Phase 243 §6 Consumer Index provides the authoritative consumer-to-delta mapping.
- **F-29-04 is explicitly NAMED in the REG-01 REQ description** — Phase 246 RE_VERIFIES the F-29-04 mid-cycle substitution envelope at HEAD `cc68bfc7`. Phase 245 GOE-01-V01 + SDR-08-V01 already produced the envelope-non-widening attestation; Task 4 of Phase 246 cites those rows as the REG-01 F-29-04 verdict (`PASS / RE_VERIFIED_AT_HEAD cc68bfc7`).
- **Preliminary F-30-NNN candidate set (planner refines, NOT mandated complete):** F-30-001 (prevrandao fallback state-machine check, touched by 771893d1 14-day grace) / F-30-005 (F-29-04 liveness-proof note, touched by 771893d1 cc68bfc7 BAF) / F-30-007 (KI-exception precedence, touched if 771893d1 introduces new path-family) / F-30-015 (prevrandao-mix recursion citation, touched by 771893d1) / F-30-017 (F-29-04 swap-site liveness recommendation, touched by 771893d1 cc68bfc7 BAF). Other F-30-NNN rows (e.g., F-30-010 EntropyLib daily-family scope note) likely UNTOUCHED and excluded. The planner walks each F-30-NNN row and applies the inclusion rule; rows excluded with one-line rationale.
- **D-09 (REG-01 verdict taxonomy per row — `PASS / REGRESSED / SUPERSEDED`):** Matches v30 REG verdict shape (v29 had 31 PASS + 1 SUPERSEDED + 0 REGRESSED; v30 had 31 PASS + 0 REGRESSED + 0 SUPERSEDED). Each touched row gets a closed verdict with evidence + cross-cite to the originating delta SHA. `SUPERSEDED` overlaps with REG-02 — if a touched row would be SUPERSEDED, it lives in REG-02 (cleaner separation per D-12).

### REG-02 SUPERSEDED Sweep Scope (Gray Area 2 — user-selected)

- **D-10 (explicit candidate list — LEAN scope):** Phase 246 enumerates a bounded, pre-identified candidate list rather than walking all v25.0 / v27.0 / v28.0 / v29.0 / v30.0 findings (50+ rows). Matches LEAN milestone scope per ROADMAP REG-01 / REG-02 phrasing ("Skip the full 31-row v30.0 regression sweep per milestone scope decision"). Cost-effective rigor — same philosophy as 244 D-02 / 245 D-12.

- **D-11 (candidates pre-identified at plan-time — frozen in 246-01-PLAN.md frontmatter):** The plan freezes the candidate list before execution begins. Frontmatter pattern (illustrative, planner refines):
  ```yaml
  supersession_candidates:
    - candidate: "Prior orphan-redemption edge case (v24.0 / v25.0 sDGNRS lifecycle)"
      delta: "771893d1 sDGNRS redemption protection"
      rationale: "Likely SUPERSEDED — sDGNRS:619 claimRedemption + handleGameOverDrain pendingRedemptionEthValue subtraction structurally closes any prior partial-state redemption gap"
    - candidate: "[planner-identified candidate 2 if any]"
      delta: "[delta SHA]"
      rationale: "[one-line rationale]"
  ```
  Pre-identified upfront makes the candidate list reviewable before execution + bounds the work scope.

- **D-12 (per-row verdict in REG-02 table + cross-cite to delta — matches v30 REG-02 table shape):** Table columns: `Prior-Finding-ID | Delta-SHA | Verdict {SUPERSEDED / NOT_SUPERSEDED / N/A} | Evidence | Citation`. Same column shape as v30 REG-02 (which had 29 rows all PASS — Phase 246's REG-02 will likely have 1-3 rows). If the candidate-list comes back all NOT_SUPERSEDED (less likely but possible), Task 4 emits a one-paragraph closure note explaining each NOT_SUPERSEDED rationale.

### FIND-01 Deliverable Shape (Gray Area 4 — auto-decided per Claude's Discretion)

- **D-13 (mirror v30 FINDINGS-v30.0.md 10-section shape verbatim with zero-rows where applicable):** Symmetry with v30 maximizes Phase 246 reviewability + future-reader benefit (a v32+ phase looking back at v30/v31 sees the same artifact shape). Zero-finding-candidate input does NOT collapse the structure — it produces a document where (a) severity counts are 0/0/0/0/0, (b) F-31-NN finding-blocks section is one paragraph of zero-attestation prose, (c) Non-Promotion Ledger is a zero-row table with explanatory header. Section structure for `audit/FINDINGS-v31.0.md`:
  1. Frontmatter (phase / plan / milestone / HEAD anchor `cc68bfc7` / requirements / phase status / write policy)
  2. Executive Summary (closure verdict summary / severity counts / D-08 rubric reference / KI gating rubric reference / forward-cite closure summary / attestation anchor)
  3. Per-Phase Sections (Phase 243 condensed / Phase 244 condensed / Phase 245 condensed) — see D-16
  4. **(Skipped — v30 §4 was Dedicated Gameover-Jackpot Section for Phase 240; no Phase 246 equivalent. The numbering jumps §3 → §5 to preserve cross-document section-number consistency with v30, OR §3 is followed by §4 = F-31-NN block. Planner picks; recommended §3 → §4 = F-31-NN block to avoid number-skipping confusion.)**
  5. F-31-NN Finding Blocks (one-paragraph zero-attestation prose; cross-cite Phase 245 §5)
  6. Regression Appendix (REG-01 + REG-02 tables per D-08..D-12)
  7. FIND-03 KI Gating Walk + Non-Promotion Ledger (zero-row variant per D-15)
  8. Prior-Artifact Cross-Cites (v30 + v29 + v28 + v27 + v25 + v24 + v11 milestone artifacts referenced in Phase 243/244/245 work)
  9. Forward-Cite Closure (D-25 carry — verifies Phase 244/245 emitted zero forward-cites; verifies Phase 246 emits zero forward-cites; matches v30 §9 pattern)
  10. Milestone-Closure Attestation (6-point per D-18)

- **D-14 (severity counts: CRITICAL 0 / HIGH 0 / MEDIUM 0 / LOW 0 / INFO 0):** Total F-31-NN: 0. Phase 245 §5 zero-state cited as evidence anchor.

- **D-15 (FIND-03 KI gating walk with zero-row Non-Promotion Ledger):** Task 5 emits a Non-Promotion Ledger table with header + zero data rows + an explanatory paragraph stating "Zero finding candidates surfaced across Phase 244 + Phase 245 → zero-row ledger; KNOWN-ISSUES.md UNMODIFIED per D-07 default path." The zero-row table preserves v30 ledger structure for symmetry; absent a Non-Promotion Ledger table at all would break v30/v31 cross-document consistency.

- **D-16 (per-phase sections — condensed summaries pointing to source artifacts):** Each per-phase section is ~150-300 lines (matches v30 § 3 Per-Consumer Proof Table ~170 lines compressed-form pattern). Content:
  - Phase 243 section: ~150 lines — delta scope (5 commits, 14 files, +187/-67) + 42 D-243-C### + 26 D-243-F### + 60 D-243-X### + 41 D-243-I### + 2 D-243-S### row counts + cross-cite `audit/v31-243-DELTA-SURFACE.md`
  - Phase 244 section: ~250 lines — 4 buckets (EVT/RNG/QST/GOX) + 87 V-row count across 19 REQs + 0 finding candidates + 7 INFO observations closed in-phase + cross-cite `audit/v31-244-PER-COMMIT-AUDIT.md` + working files
  - Phase 245 section: ~200 lines — 2 buckets (SDR/GOE) + 55 V-row count across 14 REQs + 0 finding candidates + KI envelope re-verifications (EXC-02 + EXC-03) + 17 Pre-Flag bullets all CLOSED in-phase + cross-cite `audit/v31-245-SDR-GOE.md` + working files
- Each per-phase section is a SUMMARY + POINTERS, not a re-derivation. Source artifacts retain authority.

### Phase 246 Hand-Off & Closure

- **D-17 (no F-31-NN forward-cite emission — D-25 terminal-phase rule carry from v30 D-25):** Phase 246 is the terminal v31.0 phase. Any finding that cannot close in Phase 246 routes to an explicit F-31-NN block with rollover addendum (e.g., "F-31-NN — TBD-v32" with specific carry-forward note) OR is closed via regression verdict (PASS / SUPERSEDED). With zero finding candidates from 244+245, no F-31-NN blocks are expected — the rollover-addendum mechanism is documented in CONTEXT.md for Phase 246-future-reader benefit but expected to be unused.

- **D-18 (milestone-closure attestation: 6-point format matching v30 D-26):** Task 6 emits a 6-point attestation:
  1. **HEAD anchor verified** — `git rev-parse HEAD` matches `cc68bfc7` (or current contract-tree HEAD if docs-only commits landed); `git diff cc68bfc7..HEAD -- contracts/ test/` empty
  2. **Phase 243/244/245 deliverables FINAL READ-only** — frontmatter `status: FINAL — READ-ONLY` confirmed on `audit/v31-243-DELTA-SURFACE.md` + `audit/v31-244-PER-COMMIT-AUDIT.md` + `audit/v31-245-SDR-GOE.md`
  3. **Zero forward-cites emitted by Phase 244/245/246** — grep for `forward-cite` / `defer-to-Phase-247` / `TBD-v32` produces only documented rollover addenda (zero expected)
  4. **KI envelope re-verifications confirmed** — EXC-02 + EXC-03 envelopes RE_VERIFIED_AT_HEAD `cc68bfc7` without widening (cross-cite SDR-08-V01 + GOE-01-V01 + GOE-04-V02)
  5. **Severity distribution attested** — CRITICAL 0 / HIGH 0 / MEDIUM 0 / LOW 0 / INFO 0; total F-31-NN = 0
  6. **Combined milestone closure signal** — `MILESTONE_V31_CLOSED_AT_HEAD_cc68bfc7`

- **D-19 (HEAD anchor `cc68bfc7` locked in 246-01-PLAN.md frontmatter; baseline = `7ab515fe`):** `baseline=7ab515fe`, `head=cc68bfc7`. Plan-start verifies `git diff cc68bfc7..HEAD -- contracts/ test/` is empty before locking frontmatter. Current git HEAD is `504e1e45e6` (a docs-only commit on top of cc68bfc7); contract-tree HEAD remains cc68bfc7 — Phase 246 anchors there.

### Scope Boundaries

- **D-20 (READ-only scope, no `contracts/` or `test/` writes):** Carries v28/v29/v30/Phase 243 D-22 / Phase 244 D-18 / Phase 245 D-20 + project-level `feedback_no_contract_commits.md` + `feedback_never_preapprove_contracts.md`. Writes confined to `.planning/phases/246-*/` + `audit/FINDINGS-v31.0.md` + (conditionally if D-07 promotes ≥1) `KNOWN-ISSUES.md`. With zero-finding-candidate input, the conditional KI write is expected NOT to fire — UNMODIFIED is the default outcome.

- **D-21 (upstream artifacts FINAL READ-only — `audit/v31-243-DELTA-SURFACE.md` + `audit/v31-244-PER-COMMIT-AUDIT.md` + `audit/v31-245-SDR-GOE.md` are all READ-only):** Carries Phase 244 D-20 / Phase 245 D-22. If Phase 246 reviewer finds a defect / mis-classification / scope-gap in any upstream artifact, the issue is documented in `audit/FINDINGS-v31.0.md` Task 6 attestation OR in a new F-31-NN block with rollover addendum — upstream files are NEVER edited in place. Working files (`audit/v31-244-EVT.md` / `audit/v31-244-RNG.md` / `audit/v31-244-QST.md` / `audit/v31-244-GOX.md` / `audit/v31-245-SDR.md` / `audit/v31-245-GOE.md`) are also READ-only appendices per D-21 carry.

- **D-22 (KI envelope re-verify only — no acceptance re-litigation):** Carries Phase 245 D-24. The 4 accepted RNG exceptions per `KNOWN-ISSUES.md` (EXC-01 affiliate non-VRF roll / EXC-02 Gameover prevrandao fallback / EXC-03 Gameover RNG substitution / EXC-04 EntropyLib XOR-shift) are RE_VERIFIED at HEAD `cc68bfc7` for envelope-non-widening only. Phase 246 cites Phase 245's RE_VERIFIED_AT_HEAD attestations (SDR-08-V01 + GOE-01-V01 + GOE-04-V02) — does NOT re-derive the envelope checks. Acceptance is NOT re-litigated.

- **D-23 (HEAD-drift handling — addendum cycle if any FUTURE contract commit lands):** Carries Phase 243 D-03 / Phase 244 D-19 / Phase 245 D-21 amended-HEAD pattern. If `git diff cc68bfc7..HEAD -- contracts/ test/` becomes non-empty before/during Phase 246 execution, baseline resets and Phase 246 may re-open for an addendum. Plan-start re-verifies the contract-tree HEAD is unchanged before locking the 246-01-PLAN.md frontmatter.

- **D-24 (Non-Promotion Ledger zero-row variant — UNMODIFIED default):** Per D-07 + zero-finding-candidate input, the expected FIND-03 outcome is UNMODIFIED `KNOWN-ISSUES.md`. The Non-Promotion Ledger table is published with zero data rows + explanatory header. If during Task 5 execution any candidate is identified that would clear D-06 3-predicate gating (unlikely given zero-finding-candidate input), the candidate is added to the ledger as an APPROVED entry + KNOWN-ISSUES.md is updated in the same Task 5 commit.

- **D-25 (terminal-phase rule — no forward-cites; matches v30 D-25 / Phase 245 D-23):** Phase 246 is the terminal v31.0 phase. Any finding rolled forward to v32+ requires an explicit F-31-NN rollover addendum block in §5 of `audit/FINDINGS-v31.0.md` — never an implicit "TBD" or "deferred" annotation. Default path (zero rollover) is expected given zero-finding-candidate input.

### Claude's Discretion

- Exact within-section ordering inside `audit/FINDINGS-v31.0.md` (frontmatter / executive-summary subsection ordering matches v30 verbatim by D-13; planner may compress sub-subsections if zero-finding-candidate context makes some redundant)
- Whether §3 → §4 = F-31-NN block (no §4 = "Dedicated Gameover-Jackpot Section" since v30's §4 was Phase 240-specific) OR §3 → §5 with §4 explicitly skipped + rationale note (planner picks; recommended §3 → §4 = F-31-NN per D-13 to avoid number-skipping confusion)
- Per-phase section formatting — table-first vs prose-first vs hybrid (D-16 specifies content; not format)
- Whether to include a per-phase "change count card" header in each per-phase section (mirrors Phase 244's per-bucket cards) — planner-discretion, not mandated
- F-31-NN finding-block prose-vs-table choice when emitting zero-attestation (D-13 specifies one paragraph; planner may add a sentinel "F-31-NN: NONE" header row for grep-friendliness)
- REG-01 verdict-row inclusion granularity for each F-30-NNN candidate (D-08 specifies the inclusion rule; planner walks each F-30-NNN and applies it — exact 5-7 row final list is planner-derived)
- REG-02 candidate count beyond the sDGNRS-redemption seed candidate (D-11 specifies frontmatter freeze pattern; planner may identify 0, 1, 2, or more additional candidates during plan-time research)
- Forward-cite closure summary format — table vs prose vs hybrid (D-17 specifies content; not format)
- Milestone-closure attestation format — bullet list vs numbered list vs table (D-18 specifies 6 points; format planner-discretion)
- Whether to include a "v31.0 milestone summary card" at the top of `audit/FINDINGS-v31.0.md` executive-summary section (mirrors v30 closure-verdict-summary block; matches v30 D-23 10-section shape per D-13) — recommended yes for symmetry
- Whether to commit the working files (`audit/v31-244-EVT.md` / `audit/v31-244-RNG.md` / `audit/v31-244-QST.md` / `audit/v31-244-GOX.md` / `audit/v31-245-SDR.md` / `audit/v31-245-GOE.md`) to the prior-artifact cross-cites section §8 (D-13) explicitly — planner-discretion, recommended yes per D-21

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Phase 246 scope anchors (MANDATORY — READ-only per D-21)
- `audit/v31-243-DELTA-SURFACE.md` — FINAL READ-only; §6 Consumer Index maps v31.0 REQs to D-243-X/F/C/S rows; Phase 246 §3 per-phase Phase 243 section cross-cites
- `audit/v31-244-PER-COMMIT-AUDIT.md` — FINAL READ-only; 87 V-rows across 19 REQs; §Phase-245-Pre-Flag at L2470-2521 already consumed by Phase 245 (CLOSED 17/17); Phase 246 §3 per-phase Phase 244 section cross-cites
- `audit/v31-245-SDR-GOE.md` — FINAL READ-only; 55 V-rows across 14 REQs (40 SDR + 15 GOE); §5 Phase-246-Input zero-state subsection at L1623-1637 is the explicit FIND-01/02/03 zero-pool attestation source; Phase 246 Task 3 + Task 5 cross-cite §5 directly
- `audit/KNOWN-ISSUES.md` (project-root, NOT `audit/`) — actually located at `/home/zak/Dev/PurgeGame/degenerus-audit/KNOWN-ISSUES.md`; contains 4 design-decision entries corresponding to internal EXC-01..04 envelope tags (EXC-01 affiliate non-VRF / EXC-02 Gameover prevrandao fallback / EXC-03 Gameover RNG substitution / EXC-04 EntropyLib XOR-shift); Phase 246 D-22 RE_VERIFIES envelope non-widening, no edit unless D-07 promotes a candidate
- `audit/FINDINGS-v30.0.md` — 729 lines, 10 sections; the deliverable shape template Phase 246 mirrors per D-13
- `audit/FINDINGS-v29.0.md` — 268 lines; SUPERSEDED precedent (1 row: F-25-09 EndgameModule deletion) for D-12 / Task 4 REG-02 reference

### Phase 244 working files (READ-only appendices per D-21)
- `audit/v31-244-EVT.md` — 394 lines (22 V-rows EVT-01..04)
- `audit/v31-244-RNG.md` — 447 lines (20 V-rows RNG-01..03)
- `audit/v31-244-QST.md` — 800 lines (24 V-rows QST-01..05)
- `audit/v31-244-GOX.md` — 801 lines (21 V-rows GOX-01..07)

### Phase 245 working files (READ-only appendices per D-21)
- `audit/v31-245-SDR.md` — 924 lines (40 V-rows SDR-01..08)
- `audit/v31-245-GOE.md` — 432 lines (15 V-rows GOE-01..06)

### Prior milestone corroborating artifacts (citation-only per D-22; never re-edit)
- `.planning/milestones/v30.0-phases/237-consumer-rng-inventory/` — Consumer Index foundation
- `.planning/milestones/v30.0-phases/238-per-consumer-determinism-proof/` — 19-row Gameover-Flow Freeze-Proof Subset
- `.planning/milestones/v30.0-phases/239-rnglock-state-machine/` — rngLockedFlag state-machine + asymmetry re-justification
- `.planning/milestones/v30.0-phases/240-gameover-jackpot-safety/` — GO-240-NNN consumer inventory
- `.planning/milestones/v30.0-phases/241-exception-closure/` — EXC-01..04 acceptance origin
- `.planning/milestones/v30.0-phases/242-regression-findings-consolidation/` — `audit/FINDINGS-v30.0.md` source phase (Phase 246 single-plan precedent per D-01)
- `.planning/milestones/v29.0-phases/232.1-rng-consumer-audit/` — F-29-04 commitment-window trace
- `.planning/milestones/v29.0-phases/235-trnx-rng/` — `rngLocked` 4-path walk
- v25.0 / v27.0 / v28.0 / v29.0 / v30.0 archived ROADMAP + REQUIREMENTS files in `.planning/milestones/`

### Project-level constraints (MANDATORY)
- `/home/zak/Dev/PurgeGame/degenerus-audit/CLAUDE.md` (if exists) — project instructions
- `.planning/PROJECT.md` — core value, milestone history (v31.0 milestone scope at L11-28)
- `.planning/REQUIREMENTS.md` — FIND-01..03 + REG-01..02 definitions (lines 96-105); traceability table maps all 5 REQs to Phase 246 (lines 151-155)
- `.planning/ROADMAP.md` — Phase 246 Success Criteria SC-1..SC-5 (lines 148-159); execution-order rationale at L163
- `.planning/STATE.md` — current state at v31.0 91% complete (3/4 phases done; Phase 246 next)
- Project memory: `feedback_no_contract_commits.md`, `feedback_never_preapprove_contracts.md`, `feedback_wait_for_approval.md`, `feedback_manual_review_before_push.md`, `feedback_no_history_in_comments.md`, `feedback_rng_backward_trace.md`, `feedback_rng_commitment_window.md`, `feedback_skip_research_test_phases.md`, `feedback_gas_worst_case.md`

### Contract surface references (HEAD cc68bfc7; READ-only per D-20)
- Cited in per-phase sections only — Phase 246 does NOT re-derive contract behavior from `contracts/` source. Phase 243/244/245 deliverables are the authoritative re-derivation citations.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `audit/FINDINGS-v30.0.md` — 10-section template Phase 246 mirrors per D-13 (frontmatter + executive summary + per-phase sections + F-31-NN blocks + regression appendix + KI gating walk + prior-artifact cross-cites + forward-cite closure + milestone-closure attestation)
- `audit/FINDINGS-v29.0.md` — SUPERSEDED row precedent (F-25-09) for REG-02 D-12 reference
- Phase 245 §5 Phase-246-Input zero-state subsection — pre-derived FIND-01/02/03 attestation; Task 3 + Task 5 cite directly
- Phase 244 §Phase-245-Pre-Flag CLOSED-17/17 cross-walk — confirms zero rollover from 244 to 245 (and zero rollover from 245 to 246)
- 6-point milestone-closure attestation pattern from v30 D-26 — Phase 246 D-18 carry

### Established Patterns
- Single-plan single-deliverable consolidation (v30 Phase 242 precedent) — D-01 carry
- Per-task atomic commits within a single plan (244-04 / 245-02 multi-commit pattern) — D-04 carry
- Direct write to published artifact (no working file intermediary) — D-03 carry from v30 Phase 242
- Frontmatter `status: FINAL — READ-ONLY` flip on plan-close commit — Phase 243/244/245 carry
- Cross-cite prior-milestone artifacts (citation-only, never sole warrant) — Phase 240 D-17 / 245 D-17 carry
- 5-bucket severity rubric `{CRITICAL, HIGH, MEDIUM, LOW, INFO}` — v30 D-08 carry
- 3-predicate KI gating (accepted-design + non-exploitable + sticky) — v30 D-09 carry
- D-16 default UNMODIFIED `KNOWN-ISSUES.md` path — v30 D-16 carry

### Integration Points
- Phase 246 publishes `audit/FINDINGS-v31.0.md` as the v31.0 milestone deliverable — terminal artifact
- Phase 246 Task 6 milestone-closure attestation produces the `MILESTONE_V31_CLOSED_AT_HEAD_cc68bfc7` signal that PROJECT.md / STATE.md milestone-archival workflow consumes (next milestone v32.0 boots from this signal)
- KI envelope re-verifications already attested by Phase 245 (SDR-08-V01 + GOE-01-V01 + GOE-04-V02) — Phase 246 inherits without re-derivation
- Future v32+ regression appendix consumes Phase 246 REG-01 + REG-02 outcomes as v31.0 baseline reference

</code_context>

<specifics>
## Specific Ideas

- **v30 Phase 242 single-plan precedent**: User-locked D-01 explicitly mirrors Phase 242. The mechanical structure (1 plan, 6 tasks, direct write, per-task atomic commits) is identical to Phase 242 except (a) v31 has 6 tasks rather than v30's task layout (planner verifies v30 Phase 242 exact task count), (b) v31 deliverable `audit/FINDINGS-v31.0.md` references HEAD `cc68bfc7` instead of `7ab515fe`, (c) v31 expected severity is 0/0/0/0/0 instead of v30's 0/0/0/0/17.
- **REG-02 explicit candidate list**: User-locked D-10 + D-11. The seed candidate is sDGNRS orphan-redemption (per REQ example); planner may identify 1-2 additional candidates at plan-time but list is bounded and frozen in frontmatter before execution.
- **REG-01 inclusion rule deference to planner**: User did NOT pick the REG-01 gray area, so D-08 establishes a defensible inclusion rule (domain-cite + delta-surface mapping with F-29-04 explicitly named) and lets the planner walk each F-30-NNN row applying the rule. This is a Claude's-Discretion-with-floor pattern matching 244 D-07 / 245 D-09.
- **Zero-state symmetry with v30 shape**: User did NOT pick the FIND-01 deliverable shape gray area, so D-13 takes the most defensible default — mirror v30 verbatim with zero-rows where applicable. This maximizes future-reader benefit (v32+ phases see consistent v30 / v31 artifact shapes).

</specifics>

<deferred>
## Deferred Ideas

The following ideas surfaced during analysis but were explicitly deferred from Phase 246 scope:

- **Full v30.0 31-row regression sweep** — replaced by REG-01 LEAN spot-check per ROADMAP REG-01 phrasing + D-08 inclusion rule. If a future v32+ milestone reviewer finds the LEAN spot-check insufficient, a full sweep can be re-run as a future-milestone phase (cost: ~50 prior-finding rows × delta-cross-walk).
- **Exhaustive REG-02 SUPERSEDED sweep across all v25/v27/v28/v29/v30 findings** — deferred per D-10 (user picked LEAN explicit candidate list). If Phase 246 reviewer finds the candidate list under-sampled, exhaustive sweep is a future-milestone candidate.
- **Per-finding NUMERIC severity scoring (CVSS / DREAD / etc.)** — Phase 246 uses qualitative D-08 5-bucket rubric per v29/v30 carry. Numeric scoring is a tooling-improvement candidate for a future audit-process milestone.
- **Automated FIND-01 deliverable generation from working files** — Phase 246 hand-authors `audit/FINDINGS-v31.0.md`. A future audit-tooling phase could template-generate the deliverable from frontmatter + per-phase summary YAML; that's an audit-process improvement, not a v31.0 finding.
- **KI gating predicate refinement (e.g., 4-predicate or weighted-predicate)** — D-06 carries v30 D-09's 3-predicate verbatim. Predicate refinement is a future-milestone candidate if reviewer finds the binary AND of 3 predicates over-restrictive.
- **Cross-milestone finding-ID re-numbering scheme** — F-31-NN is fresh (zero F-31-NN expected per D-14); v30's F-30-NNN, v29's F-29-NN, v28's F-28-NN, etc. are documented in their respective FINDINGS files. A future audit-meta-tooling milestone could unify to a single global F-NN scheme; not in v31.0 scope.

</deferred>

---

*Phase: 246-findings-consolidation-lean-regression-appendix*
*Context gathered: 2026-04-24*
*HEAD anchor: cc68bfc7 (verified zero contracts/ drift at CONTEXT-lock time; current git HEAD 504e1e45 = docs-only since cc68bfc7)*
