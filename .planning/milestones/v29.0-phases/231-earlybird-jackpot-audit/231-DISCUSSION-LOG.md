# Phase 231: Earlybird Jackpot Audit — Discussion Log

**Mode:** auto (no interactive questions)
**Date:** 2026-04-17
**Decisions locked:** 9 (D-01 through D-09)

## Gray Areas Surfaced

### GA-01: Plan count — 1 consolidated vs. 3 per-requirement vs. 2 (merge EBD-01+EBD-03)
- **Question:** Should EBD-01, EBD-02, EBD-03 each get their own plan file, or should they consolidate?
- **Options considered:**
  - **(a) 1 consolidated plan** with three sections — minimizes context-switching but couples unrelated commits (`f20a2b5e` for finalize vs. `20a951df` for trait-roll) and makes cherry-picking verdicts for regression later harder
  - **(b) 2 plans** — merge EBD-01 (finalize) with EBD-03 (state machine) since both touch `_finalizeEarlybird`, separate EBD-02 (trait-roll) — but EBD-03 is genuinely cross-commit and would conflate attribution
  - **(c) 3 plans** — one per EBD requirement
- **Chosen:** **(c) 3 plans** → D-01 in CONTEXT.md
- **Reasoning:** EBD-01 and EBD-02 touch different commits (`f20a2b5e` vs. `20a951df`), different files (Advance+Mint+Whale+Storage vs. Jackpot), and different invariants (CEI/reentrancy/budget vs. entropy-parity/queue-level). EBD-03 is a cross-commit trace that reads cleanest as its own plan, mirroring v24.0 Phase 203's `handleGameOverDrain` end-to-end walk style. Auto-rule 6 default. Also matches ROADMAP's "expected 2-3 plans" guidance on the upper end, justified by distinct commit attribution.

### GA-02: Artifact file layout — single AUDIT.md per plan vs. sub-artifacts per function
- **Question:** Should each plan produce one AUDIT.md, or split per-function?
- **Options considered:**
  - **(a) One AUDIT.md per plan** (3 files total: `231-01-AUDIT.md`, `231-02-AUDIT.md`, `231-03-AUDIT.md`) — matches v25.0 Phase 214's per-class artifacts (`214-01-REENTRANCY-CEI.md` etc.)
  - **(b) Per-function file** — would balloon to ~9 files for EBD-01 alone, making cross-reference hard
  - **(c) No separate artifact** — embed verdicts directly in the plan's SUMMARY.md tail — loses the table's standalone greppability
- **Chosen:** **(a) One AUDIT.md per plan** → D-01 in CONTEXT.md
- **Reasoning:** Matches the v25.0 Phase 214 precedent Claude was told to mirror. Single-file pattern is also the project default per D-05 of Phase 230. Keeps each plan's deliverable bounded and greppable.

### GA-03: Attack-vector enumeration — freeform vs. locked minimum list
- **Question:** Should the planner pick attack vectors per function, or should CONTEXT lock a minimum set?
- **Options considered:**
  - **(a) Freeform** — planner's discretion — risks missing a vector the success criteria name (CEI, reentrancy, storage ordering, budget conservation, salt-space isolation, lvl+1 queue, futurePool→nextPool)
  - **(b) Locked minimum list per requirement** — binds the planner to ROADMAP success-criteria language
  - **(c) Locked exhaustive list** — defeats the purpose of the planner
- **Chosen:** **(b) Locked minimum list** → D-08 in CONTEXT.md
- **Reasoning:** ROADMAP Phase 231 Success Criteria 1 and 2 explicitly name the attack vectors. Locking a minimum list ensures coverage; leaving a "planner may add more" escape hatch preserves flexibility. The list is keyed to requirement ID (EBD-01/02/03) so mapping stays clean.

### GA-04: Finding-ID emission — emit now vs. defer to Phase 236
- **Question:** Should Phase 231 emit `F-29-NN` IDs for its FAIL / DEFER verdicts, or only collect finding-candidate prose?
- **Options considered:**
  - **(a) Emit now** — would let Phase 231 own numbering, but creates cross-phase ID collision risk if Phase 232 / 233 / 234 / 235 also emit in parallel
  - **(b) Defer to Phase 236** — consistent with v25.0 Phase 217 / v27.0 Phase 223 consolidation-owns-IDs pattern, avoids collision
  - **(c) Reserve a range per phase** — more coordination overhead than benefit
- **Chosen:** **(b) Defer to Phase 236** → D-09 in CONTEXT.md
- **Reasoning:** Explicit user_feedback rule: "NO finding-ID emission in CONTEXT.md (findings come in Phase 236)." Matches the established milestone consolidation pattern. Phase 236 FIND-01 is already tasked with `F-29-NN` ID assignment per REQUIREMENTS.md.

### GA-05: Prior-phase verdict reuse — cite-as-exempt vs. re-audit fresh
- **Question:** Can Phase 231 inherit "PASS" verdicts from v25.0 Phase 214 or v27.0 Phase 223 for functions that were touched by `f20a2b5e` / `20a951df` but also audited previously?
- **Options considered:**
  - **(a) Inherit PASS verdicts** — saves work but carries forward stale assumptions. v25.0 Phase 214 D-02 explicitly rejected this pattern ("Fresh from scratch. Do not reference or rely on v5.0 adversarial audit artifacts")
  - **(b) Cite as regression-anchor only** — prior verdicts visible but every delta-touched function gets a fresh verdict
  - **(c) Audit only functions changed by the two commits** — matches D-03 in Phase 230 (only execution-affecting changes count as MODIFIED)
- **Chosen:** **(b) Cite as regression-anchor only, re-audit fresh every delta-touched function** → D-03 in CONTEXT.md
- **Reasoning:** Carries forward v25.0 Phase 214 D-02's "fresh-from-scratch" discipline. Prior conclusions are anchors for Phase 236 REG-01/02, not exemptions for this phase. Audit scope is the functions flagged MODIFIED/NEW in `230-01-DELTA-MAP.md` §4 Consumer Index EBD rows; unchanged functions outside the delta are not re-audited here (that is the v25.0 / v27.0 original sweep's territory).

### GA-06: Scope-gap handling — edit 230-01-DELTA-MAP vs. scope-guard deferral
- **Question:** If Phase 231 finds an earlybird-touched function that 230-01-DELTA-MAP.md missed, what does it do?
- **Options considered:**
  - **(a) Edit 230-01 in-place** — violates Phase 230 D-06 READ-only rule
  - **(b) Record scope-guard deferral** in `231-0N-AUDIT.md` citing Phase 236 REG-01 / FIND-01 as receiver — matches v28.0 D-227-10 / D-228-09 precedent
  - **(c) Fail the phase and escalate** — too heavy for what's likely minor
- **Chosen:** **(b) Scope-guard deferral** → D-06 in CONTEXT.md
- **Reasoning:** Phase 230 D-06 is canonical. User's feedback memory explicitly calls this out ("If you find a scope gap, record it as a scope-guard deferral in THIS phase's CONTEXT.md, do not edit Phase 230."). The v28.0 milestone's D-227-10 → D-228-09 chain is a working precedent.

### GA-07: Phase 235 overlap — pursue in-place vs. hand off
- **Question:** If EBD-01/02/03 surface an ETH-conservation concern or an RNG commitment-window concern, does Phase 231 close it or hand it off?
- **Options considered:**
  - **(a) Pursue in-place** — risk of shallow proof + duplicate work with Phase 235
  - **(b) Hand off to Phase 235 with the specific requirement ID** (RNG-01 / RNG-02 / CONS-01 / TRNX-01) — respects Phase 235's ownership and the milestone's dependency graph
  - **(c) Block the phase until Phase 235 runs** — inverts the dependency ordering (235 depends on 231-234 per ROADMAP)
- **Chosen:** **(b) Hand off with target requirement ID** → D-07 in CONTEXT.md
- **Reasoning:** ROADMAP ordering places Phase 235 AFTER Phases 231-234 specifically because the earlier phases surface concerns that 235 closes with algebraic/formal proofs. Duplicating the proof in 231 would waste effort; skipping the concern would lose the chain of custody. Hand-off with target ID is the clean pattern.

### GA-08: Verdict table columns — six-column vs. narrower/wider
- **Question:** Are the six locked columns (Function | File:Line | Attack Vector | Verdict | Evidence | SHA) sufficient?
- **Options considered:**
  - **(a) Six columns** (auto-rule 4 default)
  - **(b) Add a "Prior-Audit Reference" column** — mostly redundant with "Evidence" and adds width to an already-wide table
  - **(c) Drop "SHA" column** — would break auto-rule 5 traceability requirement
- **Chosen:** **(a) Six columns** → D-02 + D-05 in CONTEXT.md
- **Reasoning:** Auto-rules 4 and 5 lock this exactly. Adding columns would create inconsistency with the pattern other v29.0 adversarial phases (232/233/234) will follow. If a verdict needs cross-reference prose, it goes in the "Evidence" cell or into the findings-candidate block below the table.

### GA-09: EBD-03 artifact format — per-function table vs. path walk vs. state diagram
- **Question:** EBD-03 is a cross-function state machine trace; does the per-function verdict table fit?
- **Options considered:**
  - **(a) Force per-function table** — would duplicate EBD-01 and EBD-02 rows without adding info
  - **(b) Numbered path walk + verdict block** — matches how v24.0 Phase 203 traced the `handleGameOverDrain` end-to-end flow
  - **(c) Pure state diagram** — harder to grep
- **Chosen:** **(b) Numbered path walk + verdict block** → D-01 Specific Ideas in CONTEXT.md
- **Reasoning:** EBD-03's value is the cross-commit handoff proof, not repeated per-function verdicts. The walk enumerates normal / skip-split / gameover transitions explicitly, each with a PASS/FAIL/DEFER verdict. Matches v24.0 precedent. Still greppable via the numbered-step anchors.

## Decisions Deferred

Items left for `gsd-plan-phase` (231-01-PLAN.md / 231-02-PLAN.md / 231-03-PLAN.md) to decide:

- Exact AUDIT.md intra-file section ordering (preamble vs. table first vs. findings-candidate first)
- Whether to use a single consolidated verdict table per plan or per-function sub-tables
- ASCII state-diagram representation choice for EBD-03 (if any)
- Atomic-commit-per-plan vs. phase-close-bundle commit cadence (GSD executor standard)
- Concrete file:line citations (require reading HEAD source during plan-phase, not context-phase)

## No-Asks (Already Locked by ROADMAP / Requirements / Phase 230)

Items that did NOT need a decision in this phase because they were already locked upstream:

- **Target commits `f20a2b5e` + `20a951df`** — locked by `REQUIREMENTS.md` EBD-01 / EBD-02 explicit SHA citations
- **READ-only milestone rule (no `contracts/` or `test/` writes)** — locked by `PROJECT.md` milestone context + `feedback_no_contract_commits.md` memory entry
- **Scope source = `230-01-DELTA-MAP.md`** — locked by Phase 230 D-11 (Consumer Index maps every v29.0 requirement to specific rows) + Phase 230 D-06 (catalog READ-only after commit)
- **In-scope file set (12 files across the milestone; 6 relevant to Phase 231)** — locked by `230-01-DELTA-MAP.md` §1 subsections + `REQUIREMENTS.md` in-scope files list
- **Dependency: Phase 231 depends on Phase 230** — locked by `ROADMAP.md` Phase 231 block
- **Dependency: Phase 235 depends on Phase 231 (and 232/233/234)** — locked by `ROADMAP.md` Phase 235 block; drives the hand-off pattern in D-07
- **Dependency: Phase 236 depends on Phase 231-235** — locked by `ROADMAP.md` Phase 236 block; drives the finding-ID deferral in D-09
- **Success criteria 1-4** — locked by `ROADMAP.md` Phase 231 block; `Success Criteria 1` = per-function verdict for `f20a2b5e`, `Success Criteria 2` = per-function verdict for `20a951df`, `Success Criteria 3` = combined state-machine trace, `Success Criteria 4` = SHA + file:line citations
- **RNG-consumer handling for the earlybird bonus-trait roll** — user_feedback rule explicitly says Phase 231's EBD-02 must not conflict with Phase 235's RNG-01/02; handled by D-07 hand-off pattern
- **"Mechanical phase" plan-tight discipline** — user_feedback rule `feedback_skip_research_test_phases.md` says adversarial phases with a precise scope catalog are closer to mechanical than exploratory; reflected by the nine D-NN locks and the 3-plan structure
- **No `F-29-NN` emission** — locked by user_feedback rule "NO finding-ID emission in CONTEXT.md"
- **Plan count** — ROADMAP Phase 231 says "Plans: TBD (expected 2-3 plans, one per EBD requirement)"; this phase locks it at 3 per D-01

---

*Phase: 231-earlybird-jackpot-audit*
*Discussion log: 2026-04-17*
