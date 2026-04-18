# Phase 236: Regression + Findings Consolidation - Context

**Gathered:** 2026-04-18
**Status:** Ready for planning
**Milestone:** v29.0 — Post-v27 Contract Delta Audit (terminal phase)

<domain>
## Phase Boundary

Terminal phase of v29.0. Re-verifies all v25/v26/v27 prior findings against current code at HEAD `1646d5af`, consolidates the v29.0 phase 231-235 Finding Candidate: Y carry-ins into `audit/FINDINGS-v29.0.md` (v27.0-style per-finding blocks with `F-29-NN` IDs), updates `KNOWN-ISSUES.md` with new design-decision entries + targeted back-refs, and publishes the executive summary.

**In scope:**
- **REG-01**: Re-verify all 16 v27.0 INFO findings + 3 v27.0 KNOWN-ISSUES entries against current code
- **REG-02**: Re-verify all 13 v25.0 findings + v26.0 conclusions (no regression from the 10-commit delta)
- **FIND-01**: v27.0-style per-finding blocks in `audit/FINDINGS-v29.0.md` with severity + source phase:file:line + resolution
- **FIND-02**: Update `KNOWN-ISSUES.md` (repo root, NOT `audit/KNOWN-ISSUES.md` — ROADMAP path is a typo) with new design-decision entries referencing `F-29-NN` IDs
- **FIND-03**: Executive summary table (per-phase counts + per-severity totals) + combined deliverable published

**Explicitly NOT in scope:**
- No code changes to `contracts/` or `test/` (standing policy per `feedback_no_contract_commits.md`)
- No re-audit of phases 231-235 (done; artifacts frozen)
- No cross-repo `database/` work (that was v28.0 scope; v29.0 is contracts-only)
- Tracking sync (PROJECT.md / MILESTONES.md / REQUIREMENTS.md completion flips) is deferrable to `/gsd-complete-milestone` — planner decides whether to fold into Plan 2 or punt

</domain>

<decisions>
## Implementation Decisions

### FINDINGS-v29.0.md Shape

- **D-01:** All carry-in Finding Candidate: Y items (3 from upstream phases + 1 user-surfaced retroactive disclosure) get full v27.0-style per-finding INFO blocks with tables (Severity | Source | Contract | Function | justification paragraph | Resolution). IDs: `F-29-01`, `F-29-02` (233-01 JKP-01 event widening), `F-29-03` (234-01 QST-01 companion-test-coverage), `F-29-04` (235-05 TRNX-01 Gameover RNG substitution — user-surfaced during Phase 236 discussion).
- **D-02:** Per-phase sectioning in phase order (231 → 232 → 232.1 → 233 → 234 → 235). Phases with zero findings get a one-paragraph "zero findings" subsection; phases with findings get full per-finding blocks. Mirrors `audit/FINDINGS-v27.0.md` + `audit/FINDINGS-v28.0.md` precedent exactly.
- **D-03:** Regression Appendix is a per-item table — one row each for the 32 prior items (16 v27.0 INFO findings `F-27-01..16` + 3 v27.0 KNOWN-ISSUES entries + 13 v25.0 findings `F-25-01..13`). v26.0 is a design-only milestone with no findings to regress — include a one-paragraph "no findings" note. Columns: `ID | Severity-at-origin | Current verdict (PASS/REGRESSED/SUPERSEDED) | Evidence (file:line or commit)`. Mirrors 217-02 precedent.
- **D-04:** Executive summary uses strict v27.0 format — severity table (expected: 0 CRITICAL / 0 HIGH / 0 MEDIUM / 0 LOW / 4 INFO) + concise "Overall Assessment" paragraph noting zero on-chain vulnerabilities across 5 audit phases and 13 plans. No clean-cycle banner or marketing language — the zeros speak for themselves.

### KNOWN-ISSUES.md Policy (FIND-02)

- **D-05:** NEW KI entry — **BAF event-widening + `BAF_TRAIT_SENTINEL=420` pattern.** Disclose: "BAF jackpots use a uint16 sentinel value (420) that is out-of-domain for real uint8 traits (max=255). Event decls widened `uint8 → uint16` for BAF-capable paths to carry the sentinel. Off-chain indexers must regenerate ABIs to consume the widened type. The sentinel approach avoids introducing a separate event type while preserving structural guarantees (wider type, out-of-domain value, private visibility). Intentional design." References `F-29-01` + `F-29-02`. Consolidate the two 233-01 observations into ONE KI entry (the pattern is one design decision expressed as two event decls).
- **D-06:** NEW KI entry + `F-29-04` INFO block — **Gameover RNG substitution for mid-cycle write-buffer tickets.** Disclose: "If a mid-cycle ticket-buffer swap has occurred (daily RNG request at `AdvanceModule:292` or lootbox RNG request at `AdvanceModule:1082`) and the new write buffer is populated with tickets awaiting the expected next VRF fulfillment, a game-over event intervening before that fulfillment causes those tickets to drain against `_gameOverEntropy` (VRF-derived, with `block.prevrandao` admixture per `F-25-08` when VRF is dead 3+ days) rather than the originally-anticipated VRF word. This technically violates the 'RNG-consumer determinism' invariant — every RNG consumer's entropy should be fully committed at input time. Acceptance rationale: (a) only reachable at gameover (terminal state, no further gameplay); (b) no player-reachable exploit — gameover is triggered by 120-day liveness stall or pool deficit, neither of which an attacker can time against a specific mid-cycle write-buffer state; (c) at gameover the protocol must drain within bounded txs and cannot wait for a deferred fulfillment. All substitute entropy is VRF-derived or VRF-plus-prevrandao. Documented retroactively in Phase 236 during consolidation review; the underlying 235-05 TRNX-01 audit marked the Gameover row SAFE (Finding Candidate: N) — this is a disclosure supplement, not a re-classification." References `F-29-04`.
- **D-07:** `F-29-04` severity = **INFO**, Resolution = **DESIGN-ACCEPTED**. Matches the v29.0 exec-summary pattern (0/0/0/0/4) and mirrors the severity of the already-disclosed `F-25-08` (Gameover prevrandao fallback — same-domain acceptance).
- **D-08:** Targeted `F-29-NN` + phase back-refs on 3 existing KI entries where v29.0 re-proved the invariant:
  - `Gameover prevrandao fallback.` (already cites `F-25-08`) → append "(Re-verified v29.0 Phase 235 RNG-01; see `audit/FINDINGS-v29.0.md` regression appendix)"
  - `Decimator settlement temporarily over-reserves claimablePool.` (already cites `F-25-12`) → append "(Re-verified v29.0 Phase 235 CONS-01)"
  - `Lootbox RNG uses index advance isolation instead of rngLockedFlag.` (already cites `F-25-07`) → append "(Re-verified v29.0 Phase 235 RNG-01 + RNG-02)"
  - Other existing KI entries (`Backfill cap at 120 gap days`, `VRF swap governance`, `VRF_KEY_HASH regex`, `make -j test`, etc.) NOT touched — v29.0 scope did not exercise those code paths.
- **D-09:** 232.1 RNG-index ticket-drain ordering invariant is **NOT** promoted to a new KI entry. It is a hardening fix that made an implicit invariant explicit, not a new architectural design decision. Wardens finding the hardened code will see the explicit guard and move on — no disclosure needed.
- **D-10:** `F-29-03` (234-01 companion-test-coverage observation FC-234-A) is **NOT** promoted to KI. Test-tooling observations are not design decisions — KI is reserved for intentional architecture + accepted automated-tool findings. `F-29-03` lives only in `FINDINGS-v29.0.md`.
- **D-11:** v28.0's `D-229-10` "KI-promotion-disabled" directive does **NOT** apply to v29.0. That directive was scoped to v28 because v28 audited the simulation/database/indexer layer against contracts (not contracts themselves). v29.0 is a contract-side delta audit — KI promotion is re-enabled per normal v25/v27 pattern.

### Claude's Discretion

- **Plan split axis** — ROADMAP expects 2 plans ("one regression sweep + one consolidation, modeled on 217-01/217-02"). Default: Plan 236-01 = consolidation (FINDINGS-v29.0.md + KNOWN-ISSUES.md writes, the heavier plan), Plan 236-02 = regression appendix (32-row re-verification table). Planner may reverse the order or add a 236-03 for tracking sync.
- **Regression methodology** — Text-trace at HEAD `1646d5af` (217-02 precedent). Each of the 32 items gets a grep/code-reference-based re-verification producing a PASS/REGRESSED/SUPERSEDED verdict. No test-suite re-runs required (tests were green at HEAD per Phase 235 VERIFICATION.md `baseline_stability` note).
- **Tracking sync timing** — Lean: fold into Plan 236-02's SUMMARY.md closing block (update PROJECT.md / MILESTONES.md / REQUIREMENTS.md), OR defer entirely to `/gsd-complete-milestone` run. Planner picks based on plan-size budget.
- **F-29-01 vs F-29-02 consolidation** — The two 233-01 event-widening observations may collapse into a single `F-29-01` block (one design pattern, two event decls touched) or remain as two separate entries. Planner decides based on narrative clarity.
- **Wave structure** — Plans can run in parallel (they touch different files: 236-01 writes `audit/FINDINGS-v29.0.md` + `KNOWN-ISSUES.md`; 236-02 writes the regression appendix section inside `audit/FINDINGS-v29.0.md`). Planner may sequence to avoid merge races (236-01 first, 236-02 appends), mirroring 217 precedent.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Structural precedents (MUST mirror v27.0 format exactly)

- `audit/FINDINGS-v27.0.md` — PRIMARY structural template. Executive Summary severity table → per-phase sections → per-finding tables with `Severity | Source | Contract | Function` fields + justification paragraph + resolution rationale. 16 INFO findings + Regression Appendix.
- `audit/FINDINGS-v28.0.md` — secondary precedent with larger finding count (69 total: 27 LOW + 42 INFO). Shows same format at scale.
- `audit/FINDINGS-v25.0.md` — older precedent (13 INFO) with the original Regression Appendix pattern (`F-185-01`, `F-187-01`, I-01..I-29 vs current code).
- `audit/FINDINGS.md` — v5.0 baseline (29 INFO) — reference only; not touched by v29.0.

### Regression inputs (REG-01 + REG-02 scope)

- `audit/FINDINGS-v27.0.md` §Findings — all 16 v27.0 INFO findings (`F-27-01` through `F-27-16`) to re-verify (REG-01 scope)
- `KNOWN-ISSUES.md` — 3 v27.0 KNOWN-ISSUES entries (the ones citing `F-27-NN`: VRF_KEY_HASH regex, make -j test, Phase 222 VERIFICATION closures) to re-verify (REG-01 scope)
- `audit/FINDINGS-v25.0.md` §Findings — all 13 v25.0 findings (`F-25-01` through `F-25-13`) to re-verify (REG-02 scope)
- `.planning/MILESTONES.md` §v26.0 — v26.0 is a design-only milestone (bonus jackpot split). No findings document exists. One-paragraph "conclusions re-verified" note in Regression Appendix suffices.

### v29.0 phase deliverables (FIND-01 consolidation inputs)

- `.planning/phases/231-earlybird-jackpot-audit/231-0N-SUMMARY.md` — 3 plans, 0 Finding Candidate: Y (all SAFE; EBD-01/02/03)
- `.planning/phases/232-decimator-audit/232-0N-SUMMARY.md` — 3 plans, 0 Finding Candidate: Y (DCM-01/02/03)
- `.planning/phases/232.1-rng-index-ticket-drain-ordering-enforcement/232.1-0N-SUMMARY.md` — 3 plans, 0 Finding Candidate: Y
- `.planning/phases/233-jackpot-baf-entropy-audit/233-0N-SUMMARY.md` — 3 plans; **2 Finding Candidate: Y in 233-01** (JKP-01 BAF event-widening indexer-compat OBSERVATIONS)
- `.planning/phases/234-quests-boons-misc-audit/234-01-SUMMARY.md` — 1 plan; **1 Finding Candidate: Y** (QST-01 FC-234-A companion-test-coverage observation)
- `.planning/phases/235-conservation-rng-commitment-re-proof-phase-transition/235-0N-SUMMARY.md` — 5 plans, 0 Finding Candidate: Y (all SAFE)

### AUDIT.md sources for F-29-NN content extraction

- `.planning/phases/233-jackpot-baf-entropy-audit/233-01-AUDIT.md` — content source for `F-29-01` + `F-29-02` (BAF event widening, `BAF_TRAIT_SENTINEL` pattern, uint8→uint16 traitId)
- `.planning/phases/234-quests-boons-misc-audit/234-01-AUDIT.md` — content source for `F-29-03` (companion-test-coverage FC-234-A)
- `.planning/phases/235-conservation-rng-commitment-re-proof-phase-transition/235-05-AUDIT.md` — content source for `F-29-04` (Gameover path walk, buffer-swap semantics, `_gameOverEntropy` composition)

### Process precedents

- `.planning/milestones/v25.0-phases/217-findings-consolidation/217-CONTEXT.md` — original 2-plan split precedent
- `.planning/milestones/v25.0-phases/217-findings-consolidation/217-01-PLAN.md` — consolidation plan shape
- `.planning/milestones/v25.0-phases/217-findings-consolidation/217-02-PLAN.md` — regression appendix plan shape
- `.planning/milestones/v28.0-phases/229-findings-consolidation/229-CONTEXT.md` — most recent CONTEXT precedent (alt 2-plan split: findings + tracking sync)
- `.planning/milestones/v28.0-phases/229-findings-consolidation/229-01-CONSOLIDATION-NOTES.md` — consolidation-notes format

### Governance / policy

- `.planning/ROADMAP.md` §Phase 236 — goal, success criteria, depends-on, expected plan count
- `.planning/REQUIREMENTS.md` §Regression (REG-01/02) + §Findings Consolidation (FIND-01/02/03)
- User memory feedback: `feedback_no_contract_commits.md` — no contracts/test edits; v29.0 is doc-only
- User memory feedback: `feedback_skip_research_test_phases.md` — skip research for mechanical phases; strong 217/229 precedent = plan directly

### Writable targets (this phase produces)

- `audit/FINDINGS-v29.0.md` — **NEW file** (the deliverable)
- `KNOWN-ISSUES.md` — **UPDATE** at repo root (NOT `audit/KNOWN-ISSUES.md` — ROADMAP path is a typo; confirmed via `find . -name "KNOWN-ISSUES*"` returning only `./KNOWN-ISSUES.md`)
- `.planning/phases/236-regression-findings-consolidation/*.md` — plan artifacts
- `.planning/STATE.md` — session tracking
- (Deferred to `/gsd-complete-milestone`): `.planning/PROJECT.md`, `.planning/MILESTONES.md`, `.planning/REQUIREMENTS.md` traceability flips

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets

- **v27.0 / v28.0 structural blueprint** — `audit/FINDINGS-v27.0.md` and `audit/FINDINGS-v28.0.md` provide the exact section order, table column schema, severity-justification paragraph shape, and resolution-rationale style to mirror. Copy-paste the scaffolding, swap the content.
- **Per-phase SUMMARY.md files** at `.planning/phases/23X-*/` contain pre-compiled finding lists, counts, resolutions in the exact shape needed for consolidation — no re-derivation from AUDIT.md needed for the per-phase subsection intros.
- **STATE.md `last_activity` lines** track per-phase finding counts across the v29.0 cycle (useful for executive summary population).
- **KNOWN-ISSUES.md existing entries** provide the design-decision prose format (one-sentence headline in `**bold.**`, followed by 2-4 sentences of rationale, trailing `(See F-XX-NN in ...)` cite).
- **217-02-PLAN.md regression-row format** — each prior finding gets: ID, severity-at-origin, current status verdict, 1-2 sentence evidence with file:line. Replicate for the 32 v29.0 regression rows.

### Established Patterns

- **Commit prefix**: `docs(236): ...` or `docs(236-NN): ...` per CI convention (see `git log --oneline` for v29.0 phases)
- **Phase archive**: `.planning/phases/236-*/` stays live until `/gsd-complete-milestone` moves it to `.planning/milestones/v29.0-phases/`
- **Race-commit artifacts**: recent v29.0 phases (233, 234, 235) saw some parallel-executor race-commit subject mislabels (4a06e5af, 0e963b05, 950cc7f5). If 236 plans run in parallel, accept the same class of artifact (content in right directory is what matters; subject skew is documented, not corrected).

### Integration Points

- **No runtime integration** — this is a documentation-only phase. `audit/FINDINGS-v29.0.md` and `KNOWN-ISSUES.md` are read by external auditors (C4A wardens) and by future milestones (v30+) as input to their scope decisions.
- **External auditor-facing** — the deliverables are the entire point of v29.0. Every per-finding block, every regression row, and every KI entry must be defensible on its own against a warden reading in isolation.

</code_context>

<specifics>
## Specific Ideas

- **Expected final severity distribution**: 0 CRITICAL / 0 HIGH / 0 MEDIUM / 0 LOW / **4 INFO** (F-29-01, F-29-02, F-29-03, F-29-04) — unless planner consolidates F-29-01 + F-29-02 into a single block, in which case 3 INFO.
- **"RNG-consumer determinism" invariant** — surfaced by user during Phase 236 discussion: "there can be absolutely no non-determinism of any rng consuming stuff." This becomes a canonical protocol invariant going forward. The `F-29-04` entry and its paired KI block are the first explicit disclosures that the gameover path violates it (in a controlled, non-exploitable way). Future audits should reference this invariant by name when analyzing RNG-consuming code paths.
- **KNOWN-ISSUES.md file-path discrepancy** — ROADMAP §Phase 236 Success Criterion #4 says `audit/KNOWN-ISSUES.md` but the file lives at `./KNOWN-ISSUES.md` (repo root). Confirmed via `find`. Do NOT create a new `audit/KNOWN-ISSUES.md` — edit the existing `./KNOWN-ISSUES.md`.
- **The 233-01 event-widening observations are OFF-CHAIN indexer-compat notes, not on-chain findings**. The underlying on-chain behavior (BAF jackpots using traitId=420 sentinel) is SAFE per 233-01 AUDIT. What's disclosed is that off-chain ABI consumers must regenerate to match the widened event type. Mirror the v28.0 Phase 227 DCM-02 "indexer-compat OBSERVATION" language when writing F-29-01/02.

</specifics>

<deferred>
## Deferred Ideas

- **Cross-milestone trend analysis** (e.g., finding-rate trend across v25 → v27 → v29) — nice-to-have, not required by FIND-01/02/03. Defer to a future retrospective milestone if ever needed.
- **Documenting the "RNG-consumer determinism" invariant in a standalone reference doc** (e.g., `audit/PROTOCOL-INVARIANTS.md`) — the v29.0 KI entry discloses the one known violation but doesn't formalize the full invariant. Candidate for v30+ or an out-of-cycle documentation phase.
- **232.1 RNG-index ordering invariant as standalone KI entry** — considered during discussion, rejected (D-09). Could revisit if a future warden misreads the ordering code as arbitrary rather than enforced-by-design.
- **Tracking sync (PROJECT.md / MILESTONES.md / REQUIREMENTS.md) inside Phase 236** — likely deferred to `/gsd-complete-milestone` unless planner folds it into Plan 236-02.
- **Promotion of any v29.0 FINDING to HIGHER severity via cross-phase amplification** — none identified during this discussion. D-229-05 (v28.0 precedent) would allow promotion if cross-phase analysis revealed amplification, but v29.0 has zero findings on distinct contract surfaces, so the analysis is degenerate.

</deferred>

---

*Phase: 236-regression-findings-consolidation*
*Context gathered: 2026-04-18 — user selected 2 of 4 gray areas (FINDINGS shape + KI policy); plan split and regression methodology default to 217 precedent; user retroactively surfaced F-29-04 disclosure (gameover RNG substitution) during KI discussion*
