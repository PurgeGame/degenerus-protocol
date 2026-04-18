# Phase 232: Decimator Audit — Discussion Log

**Mode:** auto (no interactive questions)
**Date:** 2026-04-17
**Decisions locked:** 14 (D-01..D-14 in 232-CONTEXT.md)

---

## Gray Areas Surfaced

### GA-01: Plan count — one consolidated plan vs one-per-requirement?
- **Question:** DCM-01, DCM-02, DCM-03 share the same module file (`DegenerusGameDecimatorModule.sol`) and partly overlap at `claimTerminalDecimatorJackpot` (modified by both `67031e7d` and `858d83e4`). Consolidate into a single `232-01-PLAN.md` with three requirement sections (v29.0 Phase 234 "grab-bag" pattern), or split into three plans (v25.0 Phase 214 per-requirement pattern)?
- **Options considered:**
  1. Single consolidated plan with §DCM-01 / §DCM-02 / §DCM-03 subsections.
  2. Three single-file per-requirement plans.
  3. Two plans (DCM-01 + DCM-02 fused since both touch module body; DCM-03 separate since it's a wrapper-only audit).
- **Chosen:** Option 2 — three plans (`232-01`, `232-02`, `232-03`). → **D-01** in CONTEXT.md.
- **Reasoning:** Auto-mode rule #5 and ROADMAP Phase 232 explicitly expect one plan per requirement. Each DCM requirement has a distinct attack-vector axis (key alignment vs CEI/argument vs access-control/reentrancy) — fusing them dilutes the per-function verdict table's focus. Phase 234 grab-bag pattern is the exception for coincidentally-bundled grab-bag changes across different files; Phase 232's DCM trio is tightly scoped and each has enough surface to justify its own plan. Three plans also matches the v25.0 Phase 214 precedent that auto-mode rule #1 defaults to.

### GA-02: DCM-02 indexer-compat — hard observation or deferred?
- **Question:** DCM-02 success criterion explicitly mentions "indexer compatibility with v28.0 event surface." v28.0 audited the `database/` repo at commit state BEFORE `67031e7d` was shipped. Should Plan 232-02 just flag absence as an observation, deep-dive into the indexer code, or defer entirely to a future `database/` milestone?
- **Options considered:**
  1. Deep-dive into `database/` indexer files to check event-processor coverage.
  2. Flag as one-paragraph OBSERVATION citing v28.0 Phase 227 baseline; defer action to a future indexer milestone.
  3. Defer entirely (DCM-02 scope narrows to contract-side only).
- **Chosen:** Option 2 — read-only OBSERVATION in Plan 232-02; NO `database/` writes; defer indexer-side registration to future milestone. → **D-10** in CONTEXT.md.
- **Reasoning:** v29.0 PROJECT.md explicitly scopes this milestone to `contracts/` only — the `database/` repo is out of scope. Auto-mode rule #7 instructs treating indexer-compat as an audit observation, not an action item. The ROADMAP SC2 wording ("compatible with the v28.0 indexer event surface") is satisfied by documenting whether the new events require indexer updates — the update itself is not in scope. Option 1 would breach the cross-repo scope line v28.0 established. Option 3 would drop evidence the ROADMAP explicitly asks for.

### GA-03: BurnieCoin conservation scope for DCM-01 vs CONS-02
- **Question:** `3ad0f8d3` touches `BurnieCoin.decimatorBurn`. DCM-01 requires auditing the burn-key refactor; CONS-02 (Phase 235) requires proving BURNIE conservation. Does Plan 232-01 close the mint/burn accounting loop, or stop at burn-key correctness?
- **Options considered:**
  1. Plan 232-01 closes the BURNIE accounting loop (duplicates CONS-02 work in Phase 235).
  2. Plan 232-01 audits burn-key correctness only; CONS-02 owns the full conservation proof.
  3. Plan 232-01 audits burn-key AND partial conservation; CONS-02 re-verifies.
- **Chosen:** Option 2 — burn-key correctness only; conservation deferred to Phase 235 CONS-02. → **D-14** in CONTEXT.md + explicit Deferred row.
- **Reasoning:** REQUIREMENTS.md splits these cleanly — DCM-01 is a burn-KEY audit (did the right key get used?), CONS-02 is a BURNIE conservation audit (did supply close at every endpoint?). Duplicating CONS-02 logic in Phase 232 wastes effort and risks inconsistent conclusions between phases. Phase 230 Known Non-Issue #3 is explicit: "Phase 232 DCM-01 auditors should inspect the caller's use of the returned value, not the call itself." The user feedback rule also flags this split.

### GA-04: DCM-03 missing caller restriction — flag as finding or accept as design?
- **Question:** The new `DegenerusGame.claimTerminalDecimatorJackpot()` wrapper has NO access-control modifier. Is this a DCM-03 finding or intentional design?
- **Options considered:**
  1. Flag as a CRITICAL / HIGH severity finding candidate.
  2. Treat as intentional — verify that module-side gating (post-gameover + resolved terminal round) is sufficient, record as SAFE with SAFE-INFO note about layered access control.
  3. Defer verdict to Phase 236.
- **Chosen:** Option 2 — plan 232-03 verifies module-side gating is load-bearing; wrapper-level missing modifier is intentional per ID-30 NatSpec ("post-GAMEOVER callable by anyone; level read from resolved claim round"). → **D-11** in CONTEXT.md.
- **Reasoning:** The sibling wrapper `claimDecimatorJackpot(uint24 lvl)` (pre-existing, unchanged) follows the same pattern — no modifier; module gates internally. Adding a modifier to the new wrapper while the sibling lacks one would be asymmetric. ROADMAP SC3 lists "caller restriction enforced" as a criterion — that's satisfied by the module-side gate, not the wrapper. Plan 232-03 MUST verify module gating is actually gating (not empty) before accepting this verdict — if the module lacks its own check, the verdict flips to finding candidate.

### GA-05: Reentrancy surface for `claimTerminalDecimatorJackpot` — full re-audit or delegatecall-alignment only?
- **Question:** DCM-03 SC3 lists "no reentrancy" as a criterion. The wrapper is selector-delegatecall; the module body calls `_creditClaimable` and `_consumeTerminalDecClaim`. Does Plan 232-03 re-audit all nested call paths, or rely on v25.0's prior audit of the module body + corroborate via `make check-delegatecall`?
- **Options considered:**
  1. Full re-audit of every nested call from wrapper through module body.
  2. Audit only the `858d83e4` delta (wrapper body); inherit v25.0 verdict for pre-existing module internals.
  3. Narrow to the specific new-emission path (`67031e7d`) in the module body.
- **Chosen:** Option 2 — plan 232-03 audits the wrapper-body delta; module internals inherit v25.0 Phase 214's SAFE verdict. DCM-02 (Plan 232-02) covers the `67031e7d` emission-site CEI. → **D-11** in CONTEXT.md (reentrancy sub-bullet).
- **Reasoning:** Phase 232 is a DELTA audit per milestone title. Re-auditing `_creditClaimable` / `_consumeTerminalDecClaim` internals would duplicate v25.0 Phase 214 work — none of those internals changed in the 10-commit v29.0 delta (they don't appear in §1.3 hunks). `make check-delegatecall` 44/44 PASS (§3.5) is independent evidence the selector is correct. Option 1 would bloat the plan; option 3 artificially splits reentrancy between DCM-02 and DCM-03.

### GA-06: Verdict column schema — v25.0 Phase 214 fixed columns vs DCM-specific attack-vector columns?
- **Question:** Should each plan's verdict table use a standard 6-column layout (Function | File:Line | Attack Vector | Verdict | Evidence | SHA), or customize columns per requirement (e.g., DCM-01 adds a "Key Used" column; DCM-03 adds "Caller Restriction" / "Reentrancy" / "Param Pass-through" / "Privilege Escalation" as separate columns)?
- **Options considered:**
  1. Fixed 6-column schema across all three plans (auto_mode rule #3).
  2. Per-plan customized columns reflecting each DCM requirement's attack axes.
  3. Fixed 6 columns + per-plan addenda rows beneath the table for requirement-specific deep-dives.
- **Chosen:** Option 3 — fixed 6-column schema as the primary table; each plan appends requirement-specific narrative / sub-tables after the table as Evidence expansion. → **D-02** in CONTEXT.md.
- **Reasoning:** Auto_mode rule #3 defaults to fixed columns. Phase 236 regression/consolidation reads finding candidates as a flat pool — uniform columns simplify aggregation. Requirement-specific depth (e.g., DCM-03's four SC3 axes) fits naturally into the `Attack Vector` column with one row per attack vector per function; the narrative addenda handle anything not row-shaped.

### GA-07: Do we audit the AdvanceModule consolidated-block tail in Plan 232-01 even though it's "IM-06" (an Advance-module row)?
- **Question:** §2.2 IM-06 credits the consolidated jackpot-block merge to `3ad0f8d3` but the owning FILE is `DegenerusGameAdvanceModule.sol` (not the DecimatorModule). Phase 231 (Earlybird) also audits AdvanceModule. Who owns it?
- **Options considered:**
  1. Plan 232-01 owns the consolidated-block tail audit (follows the commit, not the file).
  2. Phase 231 owns it because AdvanceModule is its primary file.
  3. Split: Phase 231 audits the non-decimator part of `_consolidatePoolsAndRewardJackpots`; Phase 232 audits the decimator-specific tail.
- **Chosen:** Option 1 — Plan 232-01 owns the consolidated jackpot-block tail because it's a DCM-01 commit (`3ad0f8d3`). → **D-07** in CONTEXT.md.
- **Reasoning:** §4 Consumer Index explicitly maps DCM-01 to "§1.1 (`_consolidatePoolsAndRewardJackpots` MODIFIED by 3ad0f8d3), §2.2 IM-06." Phase boundaries follow commits, not files — a single commit is audited exactly once. ROADMAP SC1 literal text lists "consolidated jackpot block has correct ordering" as DCM-01's responsibility. Phase 231 will audit other AdvanceModule hunks (e.g., `f20a2b5e` earlybird finalize, `52242a10` entropy passthrough) from different commits.

---

## Decisions Deferred

None — all gray areas resolved in auto-mode. The Deferred section of CONTEXT.md names three concrete deferrals (Phase 235 CONS-02 for conservation, Phase 236 FIND-01..03 for finding-ID assignment + KNOWN-ISSUES, out-of-scope `database/` repo for actual indexer registration).

---

## No-Asks (Already Locked by ROADMAP / Requirements / Phase 230)

- **Milestone read-only rule.** v29.0 PROJECT.md + STATE.md block `contracts/` and `test/` writes. Not re-debated.
- **Phase 230 catalog READ-only.** Per Phase 230 D-06, 230-01-DELTA-MAP.md cannot be edited by downstream phases. Scope gaps become scope-guard deferrals in THIS phase's CONTEXT.md (→ D-05).
- **Commit-SHA citation rule.** Auto_mode rule #4 + ROADMAP SC4 mandate commit-SHA citation on every verdict. Not re-debated (→ D-03).
- **Phase dependency.** ROADMAP: Phase 232 depends on Phase 230 only; Phase 230 is complete per STATE.md. Parallel with Phases 231/233/234. Not re-debated.
- **No F-29-NN emission.** REQUIREMENTS.md + user_feedback_rules: finding-ID assignment is Phase 236's exclusive job. Not re-debated (→ D-13).
- **Scope source.** Auto_mode rule #6 + Phase 230 §4 Consumer Index fix 230-01-DELTA-MAP.md as the exclusive scope source. Not re-debated (→ D-04).
- **Automated-gate re-runs.** `make check-interfaces`, `make check-delegatecall`, `make check-raw-selectors`, `forge build` already PASS at HEAD per §3.4 + §3.5. Plans cite §3.5 as corroborating evidence; no re-run required in Phase 232.
- **BurnieCoin accounting loop scope.** Split between DCM-01 (burn-key only) and CONS-02 (conservation) is fixed by REQUIREMENTS.md. Not re-debated (→ D-14).

---

*Phase: 232-decimator-audit*
*Discussion logged: 2026-04-17*
