# Phase 247: Delta Extraction & Classification — Context

**Gathered:** 2026-04-30
**Status:** Ready for planning

<domain>
## Phase Boundary

Produce the authoritative v32.0 audit-surface catalog: per-source function-level changelog, function classification taxonomy, and downstream call-site enumeration covering the 5 contract-touching commits between v31.0 HEAD `cc68bfc7` and current HEAD `acd88512`. Phases 248-252 consume this catalog as their sole scope input — no additional discovery required downstream.

The new `acd88512` commit (`fix(advance): guard turbo block + make _backfillGapDays idempotent`) lands the WIP turbo guard at L173 (`!rngLockedFlag`) plus the WIP backfill idempotency guard at L1167 (`rngWordByDay[idx + 1] == 0`) — applied during this discuss-phase session per Phase 247 anchoring decision (D-247-01) so the catalog references real SHAs throughout. ContractAddresses.sol working-tree changes are deploy regeneration noise and explicitly out of catalog scope. Untracked test/edge/LastPurchaseDayRace.test.js is deferred to Phase 251 along with all other test/ inventory.

Phase 247 is a pure-catalog phase with no contract or test writes regardless of milestone-level READ-only-LIFTED posture. Finding-ID emission is deferred to Phase 253 (FIND-01..04); Phase 247 produces rows + classifications + call-site maps + Consumer Index that become the finding-candidate pool for Phase 248-252 adversarial work.

Three requirements:

- **DELTA-01** — Per-source function / state variable / event inventory for all 5 commits with per-source and aggregate counts, reproducible via documented `git diff` commands
- **DELTA-02** — Every changed function labeled with one of {NEW, MODIFIED_LOGIC, REFACTOR_ONLY, DELETED, RENAMED}, with diff hunks cited and hunk-level annotation attached (zero unclassified)
- **DELTA-03** — Every changed function's and interface's downstream call sites enumerated across `contracts/` via reproducible grep (zero caller unaccounted for)

</domain>

<decisions>
## Implementation Decisions

### Anchor & Scope Boundary
- **D-247-01 (HEAD anchor `acd88512`, baseline `cc68bfc7`):** Phase 247 anchors at v31.0 HEAD `cc68bfc7` → current HEAD `acd88512`. Range: `cc68bfc7..acd88512`. **5 contract-touching commits:**
  1. `8bdeabc2` — fix(liveness): pause death clock during productive multi-call window (`DegenerusGameAdvanceModule.sol`)
  2. `ad41973c` — test(liveness): cover productive-phase pause regression (test/ files only — out of catalog scope per D-247-02)
  3. `6a63705b` — fix(mint): charge buyer not operator for purchaseCoin tickets (`DegenerusGameMintModule.sol`)
  4. `48554f8f` — refactor(vault): decouple share redemption from game operator approval (`DegenerusVault.sol`, `DegenerusGameStorage.sol` + tests out of scope)
  5. `acd88512` — fix(advance): guard turbo block + make _backfillGapDays idempotent (`DegenerusGameAdvanceModule.sol`) — created during this discuss-phase session by committing the audit-target WIP guards. Anchor decision (Option B during discussion) was: commit the WIP first so Phase 247's catalog references real SHAs throughout.
- **D-247-02 (contracts/ only — Phase 243 D-14 carry-forward):** Call-site enumeration (DELTA-03) covers `contracts/` tree only. `test/` is out of Phase 247 scope; Phase 251 (Reproduction Tests, TST-01..04) owns all test/ inventory including the untracked `test/edge/LastPurchaseDayRace.test.js` and all delta-touched test/ files (LivenessMidJackpot, LivenessProductivePause, CoverageGap222, VaultHandler, DegenerusVault unit). `contracts/mocks/`, `contracts/test/`, `scripts/`, `deploy/` also out of scope (Phase 243 D-14 boundary preserved).
- **D-247-03 (ContractAddresses.sol — out of catalog scope):** `contracts/ContractAddresses.sol` working-tree modifications are deploy-time address regeneration (28 address constants + DEPLOY_DAY_BOUNDARY change). Regenerates on every deploy — not part of audit-target commit history. Phase 247 anchors at HEAD `acd88512` (committed) and ignores the working tree. ContractAddresses.sol gets no row, no section, no acknowledgment block in the catalog. Distinct from Phase 243 D-13 `NO_CHANGE (docs-only)` for `ffced9ef` because that was a real commit; here the file is just dirty in the working tree against `acd88512`.
- **D-247-04 (4 contract files in scope):** After D-247-02 + D-247-03 narrow the surface, Phase 247 catalog covers exactly 4 contract files:
  - `contracts/DegenerusVault.sol` — touched by `48554f8f` (heavy delta, +83/-83 net trim per Vault refactor)
  - `contracts/storage/DegenerusGameStorage.sol` — touched by `48554f8f` (+12 lines)
  - `contracts/modules/DegenerusGameMintModule.sol` — touched by `6a63705b` (+9/-? per buyer-vs-operator charge fix)
  - `contracts/modules/DegenerusGameAdvanceModule.sol` — touched by `8bdeabc2` (liveness pause) AND `acd88512` (turbo + backfill guards)
- **D-247-05 (READ-only LIFTED at milestone, but Phase 247 itself is pure-catalog):** v32.0 lifted the v28-v31 READ-only audit posture for the milestone overall. Phase 247, being pure-catalog/enumeration, has no contract or test writes regardless. Writes confined to `.planning/phases/247-*/` and `audit/v32-247-*` files. `KNOWN-ISSUES.md` is not touched in Phase 247 (KI promotions are Phase 253 FIND-03 only).

### Change Significance Taxonomy (DELTA-02) — Phase 243 D-04 carry-forward
- **D-247-06 (5-bucket classification + REFACTOR_ONLY burden of proof):** Every changed function classified as one of {NEW, MODIFIED_LOGIC, REFACTOR_ONLY, DELETED, RENAMED} per Phase 243 D-04 definitions:
  - **NEW** — Function did not exist at baseline `cc68bfc7`; appears at HEAD `acd88512` with a body.
  - **MODIFIED_LOGIC** — Function existed at baseline and HEAD; any state write, external call, control-flow branch, emitted event, or return-path evaluation changed.
  - **REFACTOR_ONLY** — Function existed at baseline and HEAD; source-level shape changed (whitespace, parens, local variable names, multi-line decomposition, tuple destructuring, NatSpec, parameter rename) but execution trace is byte-equivalent. Burden of proof on REFACTOR_ONLY — any doubt escalates to MODIFIED_LOGIC.
  - **DELETED** — Function existed at baseline; absent at HEAD.
  - **RENAMED** — Same signature body at HEAD under a different name.
- **D-247-07 (borderline-case rubric, pre-locked verdicts):** Pre-locked verdicts for known boundary cases in the 5-commit surface:
  - `acd88512` `advanceGame` turbo block at L173: MODIFIED_LOGIC (control-flow branch added — `&& !rngLockedFlag` is a new conjunctive guard).
  - `acd88512` `rngGate` (or wherever the L1167 backfill guard sits): MODIFIED_LOGIC (control-flow branch added — `&& rngWordByDay[idx + 1] == 0` is a new conjunctive guard).
  - `8bdeabc2` liveness-pause-related functions in AdvanceModule: MODIFIED_LOGIC (death clock state change — pause/resume is control-flow).
  - `6a63705b` `purchaseCoin` (or whatever MintModule function changed): MODIFIED_LOGIC (caller-vs-operator charge swap is an external-call target change).
  - `48554f8f` Vault redemption decoupling: classification per-function — most likely MODIFIED_LOGIC for the redemption flow (operator-approval gate removal is control-flow); REFACTOR_ONLY for any pure-rename-and-relocate hunks.
  - `48554f8f` GameStorage `+12 lines`: NEW for any new storage variables; classification per-row.
- **D-247-08 (hunk-level annotation required for every row):** Every classification row cites the exact diff hunk (file:line-range at HEAD with `+` / `-` markers or `git show {sha} -L <start>,<end>:<file>` reference) and a one-line semantic annotation. No row is "classification without citation" (Phase 243 D-06 carry-forward).

### Output Structure — Phase 243 D-07 / D-08 / D-09 carry-forward
- **D-247-09 (single consolidated deliverable `audit/v32-247-DELTA-SURFACE.md`):** One consolidated file matching v29 Phase 230 / v30 Phase 237 / v31 Phase 243 single-file pattern. 7 sections:
  1. Per-source changelog — function/state/event inventory grouped by commit, one row per changed symbol (DELTA-01)
  2. Aggregate function classification table — every changed function with verdict + hunk citation (DELTA-02)
  3. Downstream call-site catalog — every changed function + changed interface method with every caller across `contracts/` tree (DELTA-03)
  4. State variable / event inventory — per-source new/modified/deleted state variables and events; covers `DegenerusGameStorage.sol` +12-line storage delta (DELTA-01 state-var coverage)
  5. Storage slot layout diff — `forge inspect` output before/after for `DegenerusGameStorage.sol` (slot-by-slot, flagging any non-append change)
  6. Consumer Index — v32.0 requirement (BFL/PLV/SIB/POST31/FIND/REG) → Phase 247 section/row-ID mapping
  7. Reproduction recipe appendix — all `git diff` / `git show` / `grep` / `forge inspect` commands concatenated for reviewer replay
- **D-247-10 (tabular, grep-friendly, no mermaid):** Phase 243 D-08 carry-forward. Changelog columns: `Row ID | Commit SHA | File:Line-Range | Symbol Kind (func/state/event/interface) | Symbol Name | Change Type | One-Line Semantic Note`. Classification columns: `Row ID | Function Signature | File:Line | Classification | Hunk Ref | One-Line Rationale`. Call-site columns: `Changed Function/Interface Method | Caller File:Line | Caller Function | Call Type (direct/delegatecall/self-call) | Grep Command Used`.
- **D-247-11 (Row ID format `D-247-NNN`):** Zero-padded three-digit index. Suggested prefixes: `D-247-C###` (changelog), `D-247-F###` (classification/function), `D-247-S###` (state/event/storage), `D-247-X###` (call-site cross-ref), `D-247-I###` (consumer index entry). Final naming is planner's call — must be consistent and documented in section 1 legend.

### Plan Topology — Single Plan (D-247-12)
- **D-247-12 (single-plan `247-01-DELTA-SURFACE.md`):** v32.0 contract surface (5 commits, 4 files) is small enough that a 3-plan split (Phase 243 D-10) adds orchestration overhead without proportional parallelism benefit. One plan does DELTA-01 + DELTA-02 + DELTA-03 in sequence within a single executor session. Matches v30 Phase 242 + v31 Phase 246 single-plan multi-task pattern.
- **D-247-13 (single-plan task ordering):** Within `247-01-DELTA-SURFACE.md`, recommended task order:
  1. **Task 1 (DELTA-01 enumeration)** — `git diff cc68bfc7..acd88512 -- contracts/` + per-commit `git show {sha} -- contracts/` to produce per-source changelog rows. Storage slot diff (`forge inspect`) for GameStorage. Light reconciliation against v31 Phase 243 catalog per D-247-19.
  2. **Task 2 (DELTA-02 classification)** — Iterate the row list from Task 1; assign 5-bucket classification + hunk citation + one-line rationale per row.
  3. **Task 3 (DELTA-03 call-site catalog)** — `grep -rn` for every changed function + interface method across `contracts/`; record caller file:line + call type per row.
  4. **Task 4 (Consumer Index + reproduction recipe + final assembly)** — Map Phase 248..253 REQ-IDs (BFL/PLV/SIB/POST31/FIND/REG) to row IDs from Tasks 1-3; collect all reproduction commands; write final `audit/v32-247-DELTA-SURFACE.md` with 7 sections.
  5. **Task 5 (READ-only flip)** — Mark `audit/v32-247-DELTA-SURFACE.md` FINAL READ-only on plan-close commit per D-247-21.
- **D-247-14 (atomic per-task commits inside the plan):** Each task lands its own commit so git-blame stays granular even within the single plan. Mirrors v31 Phase 246 atomic-task-commit pattern.

### Scope Boundaries — Phase 243 D-13 / D-14 / D-15 / D-16 carry-forward (with v32.0 amendments)
- **D-247-15 (interface drift scope):** For every changed interface method in `IDegenerusGame`, `IDegenerusVault` (if `48554f8f` touches it), `IDegenerusGameStorage` (if affected by GameStorage delta), `IDegenerusGameMintModule`, `IDegenerusGameAdvanceModule` — call-site catalog enumerates all call sites including self-calls via `IDegenerusGame(address(this))`. Phase 243 D-15 pattern.
- **D-247-16 (storage layout diff included in Phase 247 — not deferred):** `DegenerusGameStorage.sol` (+12 lines from `48554f8f`) slot layout diff is produced by Phase 247 Task 1 as part of the state variable inventory (DELTA-01 covers "state variable changed"). Phase 250 SIB-04 / Phase 252 POST31-01 use Phase 247's slot-layout diff as scope input. Rationale: layout IS delta data, keeps "sole scope input" invariant from ROADMAP Phase 247 success criteria.
- **D-247-17 (test/ enumeration deferred to Phase 251):** All test/ delta enumeration deferred to Phase 251 per D-247-02. Phase 251 owns: `test/edge/LivenessMidJackpot.test.js` (`ad41973c` +225), `test/edge/LivenessProductivePause.test.js` (`ad41973c` +132), `test/fuzz/CoverageGap222.t.sol` (mods), `test/fuzz/handlers/VaultHandler.sol` (mods), `test/unit/DegenerusVault.test.js` (trim), and untracked `test/edge/LastPurchaseDayRace.test.js`.

### Methodology — Phase 243 D-17 / D-18 / D-19 carry-forward
- **D-247-18 (fresh + light reconciliation):** Task 1 enumerates FRESH via `git diff cc68bfc7..acd88512 -- contracts/` without reference to prior catalogs. Light reconciliation against v31 Phase 243 catalog `audit/v31-243-DELTA-SURFACE.md` for any v31 row whose underlying function is touched by v32 deltas. Narrower than Phase 237's full prior-artifact cross-check because v31.0 was already a complete delta audit at `cc68bfc7`.
- **D-247-19 (grep-reproducibility mandate for DELTA-03):** Every call-site catalog row carries the exact `grep` command used to find it. Aggregate reproduction recipe appendix lists all commands so a reviewer can replay Phase 247 from shell. Commands use portable POSIX syntax (no GNU-isms). If any `grep` produces output > 50 lines, truncate to the first 50 rows with an ellipsis annotation.
- **D-247-20 (classification evidence burden):** Every MODIFIED_LOGIC / REFACTOR_ONLY verdict carries hunk citation AND a one-line rationale naming the specific execution-trace-changing element (SSTORE, external call, branch, emit, return-path) OR the specific non-execution-changing element (whitespace, rename, multi-line split). No hand-wave "looks like a refactor" verdicts.

### Finding-ID Emission & Scope-Guard Handoff — Phase 243 D-20 / D-21 carry-forward
- **D-247-21 (no F-32-NN emission — Phase 253 owns it):** Phase 247 does NOT emit `F-32-NN` finding IDs. Produces rows + classifications + call-site maps that become Phase 248-252 scope input and eventual Phase 253 finding-candidate pool. If Task 1 fresh sweep uncovers a symbol Phase 248-252 plans would benefit from pre-flagging (e.g., a dropped function with no caller accounted for, or a v31-touched-now-modified-again RNG path), it goes in a `Finding Candidates` subsection with file:line + proposed severity for Phase 253 routing.
- **D-247-22 (Phase 247 output READ-only after plan-close — scope-guard deferral rule):** `audit/v32-247-DELTA-SURFACE.md` and any companion files are READ-only after Phase 247 closes. If Phase 248-252 finds a changed function, state-var, event, interface method, or call site NOT in the catalog, it records a scope-guard deferral in its own plan SUMMARY; Phase 247 output is not re-edited in place. Gaps become Phase 253 finding candidates. Phase 243 D-21 pattern.

### Claude's Discretion
- Exact section ordering within `audit/v32-247-DELTA-SURFACE.md` (planner picks most readable of the 7 sections in D-247-09)
- Whether to produce a small companion "per-source change count card" one-line summary per commit for Phase 248-252 plan-writing convenience
- Final Row ID prefix scheme (D-247-11 suggests `D-247-C/F/S/X/I-NNN` — planner may flatten to `D-247-NNN` if cleaner)
- Whether to preserve raw `git diff` output inline vs link to companion files when a single commit's diff exceeds ~200 lines (likely only `48554f8f` Vault refactor approaches this threshold)
- Whether DELTA-03 call-site grep separates direct calls from delegatecall selectors in output (nice-to-have, not mandated)
- How to handle `DegenerusVault.sol` REFACTOR_ONLY-vs-MODIFIED_LOGIC borderline rows — D-247-06's burden of proof rule applies; planner final call on per-row verdict
- Whether the new GameStorage `+12 lines` lands as one consolidated "storage block added" entry or row-per-variable

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Milestone scope (MUST read)
- `.planning/REQUIREMENTS.md` — v32.0 requirements: DELTA-01, DELTA-02, DELTA-03 (this phase) + full catalog this phase defines the surface for (BFL/PLV/SIB/TST/POST31/FIND/REG)
- `.planning/ROADMAP.md` — Phase 247 success criteria (4 items); execution-order narrative; deliverable target `audit/v32-247-DELTA-SURFACE.md`
- `.planning/PROJECT.md` — Current Milestone section lists the bug context + READ-only-LIFTED write policy

### In-scope commits (chronological order, anchored at `cc68bfc7..acd88512`)
- `8bdeabc2` — fix(liveness): pause death clock during productive multi-call window (`contracts/modules/DegenerusGameAdvanceModule.sol`)
- `ad41973c` — test(liveness): cover productive-phase pause regression (test/ files only — out of catalog scope per D-247-02)
- `6a63705b` — fix(mint): charge buyer not operator for purchaseCoin tickets (`contracts/modules/DegenerusGameMintModule.sol`)
- `48554f8f` — refactor(vault): decouple share redemption from game operator approval (`contracts/DegenerusVault.sol`, `contracts/storage/DegenerusGameStorage.sol` + tests out of scope)
- `acd88512` — fix(advance): guard turbo block + make _backfillGapDays idempotent (`contracts/modules/DegenerusGameAdvanceModule.sol`) — landed during this discuss-phase session

### In-scope files (4 contract files at `cc68bfc7..acd88512`)
- `contracts/DegenerusVault.sol` (touched by `48554f8f` — heavy delta)
- `contracts/storage/DegenerusGameStorage.sol` (touched by `48554f8f` — +12 lines)
- `contracts/modules/DegenerusGameMintModule.sol` (touched by `6a63705b`)
- `contracts/modules/DegenerusGameAdvanceModule.sol` (touched by both `8bdeabc2` and `acd88512`)

### Methodology precedents (carried forward, not re-litigated)
- `.planning/milestones/v31.0-phases/243-delta-extraction-per-commit-classification/243-CONTEXT.md` — direct precedent. D-04 5-bucket classification, D-06 hunk citation, D-07 single deliverable, D-08 tabular grep-friendly, D-09 row ID format, D-10/D-11 plan topology (modified to single-plan here), D-13 NO_CHANGE row pattern (not used here per D-247-03), D-14 contracts-only scope, D-15 interface drift, D-16 storage layout, D-17 fresh+reconciliation, D-18 grep mandate, D-19 evidence burden, D-20 no finding-ID emission, D-21 scope-guard deferral, D-22 READ-only — all mirrored into v32 numbering.
- `.planning/milestones/v31.0-phases/243-delta-extraction-per-commit-classification/243-*-PLAN.md` — prior plan deliverable shape (single-plan in v32 supersedes 3-plan split)
- `audit/v31-243-DELTA-SURFACE.md` — direct format precedent for `audit/v32-247-DELTA-SURFACE.md` shape (7 sections, tabular, grep-friendly)
- `.planning/milestones/v30.0-phases/237-vrf-consumer-inventory-call-graph/237-CONTEXT.md` — earlier 3-plan precedent showing where the v32 single-plan diverges
- `.planning/milestones/v30.0-phases/242-findings-consolidation/` — single-plan multi-task pattern reference (D-247-12)
- `.planning/milestones/v31.0-phases/246-findings-consolidation-lean-regression-appendix/` — single-plan multi-task atomic-commit pattern reference (D-247-14)

### Prior audit outputs (light reconciliation per D-247-18)
- `audit/v31-243-DELTA-SURFACE.md` — primary D-247-18 reconciliation target. Cross-check any v31-row whose underlying function is touched by v32 deltas (especially AdvanceModule which receives both `8bdeabc2` and `acd88512` hunks; MintModule which received QST-related hunks in v31; Vault which touched sDGNRS redemption in v31 `771893d1`).
- `audit/FINDINGS-v31.0.md` — v31.0 findings context; any prior finding on a v32-delta-touched function routes to Phase 253 REG-01/02 supersession check.
- `audit/FINDINGS-v30.0.md`, `audit/FINDINGS-v29.0.md` — earlier findings; Phase 253 REG-01 may consult these if a v32-delta-touched function carries earlier findings.
- `audit/KNOWN-ISSUES.md` — 4 accepted RNG exceptions (EXC-01 affiliate roll / EXC-02 prevrandao fallback / EXC-03 F-29-04 mid-cycle substitution / EXC-04 EntropyLib XOR-shift). Any delta that widens these re-opens Phase 248 BFL-05 / Phase 252 POST31-01 sub-audit.
- `audit/STORAGE-WRITE-MAP.md` — prior storage-write catalog; `DegenerusGameStorage.sol` slot-layout diff references this for format precedent.
- `audit/ACCESS-CONTROL-MATRIX.md` — prior access-control context; relevant to `48554f8f` Vault redemption operator-approval decoupling and `6a63705b` MintModule charge-target swap.

### Project feedback rules (apply across all plans in Phase 247 and downstream)
- `memory/feedback_no_contract_commits.md` — explicit per-commit user approval required for any `contracts/` or `test/` write. v32.0 lifted READ-only at milestone level but per-commit approval rule still binds.
- `memory/feedback_contract_locations.md` — `contracts/` is the only authoritative source.
- `memory/feedback_no_history_in_comments.md` — deliverable docs describe what IS, not what CHANGED (except where change-tracking is the entire point — i.e., the changelog section in DELTA-SURFACE.md).
- `memory/feedback_contractaddresses_policy.md` — ContractAddresses.sol is modifiable without contract-commit approval per project policy; relevant to D-247-03 (working-tree state ignored at HEAD anchor).
- `memory/feedback_rng_backward_trace.md` + `feedback_rng_commitment_window.md` — relevant to Phase 248 BFL-04 / Phase 249 PLV-02 (downstream consumers) but Phase 247 is pre-finding so these don't bind here.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- **Phase 243 `audit/v31-243-DELTA-SURFACE.md` 7-section single-file format** — directly reusable for `audit/v32-247-DELTA-SURFACE.md`; same section layout (per-source changelog / classification table / call-site catalog / state-var inventory / storage slot diff / Consumer Index / reproduction recipe).
- **Phase 243 `243-01-PLAN.md` / `243-02-PLAN.md` / `243-03-PLAN.md` 3-plan split** — partial reuse; v32 single-plan inherits the per-task structure but compresses 3 plans → 1 plan with 5 tasks (per D-247-12 / D-247-13).
- **Phase 246 `246-01-PLAN.md` single-plan multi-task atomic-commit pattern** — direct reuse for D-247-13 / D-247-14 task ordering and per-task commits.
- **Existing `audit/` deliverables** — `STORAGE-WRITE-MAP.md`, `ETH-FLOW-MAP.md`, `ACCESS-CONTROL-MATRIX.md`, `FINDINGS-v*.md`, `v31-*.md`, `v30-*.md`, `v29-*.md` series — file-format precedents; `v32-*` namespace is fresh for this milestone.
- **Makefile gates** — `check-interfaces`, `check-delegatecall`, `check-raw-selectors` already enforce interface↔implementation alignment; Phase 247 does NOT duplicate these gates, only catalogs the surface.

### Established Patterns
- **HEAD anchor in plan frontmatter** — Phase 230 D-06 / Phase 237 D-17 / Phase 243 D-03; applied here as D-247-01.
- **No finding-ID emission in enumeration phases** — Phase 230 D-06 / Phase 237 D-15 / Phase 243 D-20; applied as D-247-21.
- **Scope-guard deferral rule** — downstream phases record deferrals instead of editing prior-phase output; applied as D-247-22.
- **Fresh-first + reconciliation** — Phase 237 D-07 two-pass / Phase 243 D-17 lighter; applied as D-247-18.
- **Single-file consolidated deliverable** — Phase 230 D-05 / Phase 237 D-08 / Phase 243 D-07; applied as D-247-09.
- **Tabular grep-friendly, no mermaid** — Phase 230 D-08 / Phase 237 D-09 / Phase 243 D-08; applied as D-247-10.
- **Single-plan multi-task atomic commits** — v30 Phase 242 / v31 Phase 246; applied as D-247-12 / D-247-13 / D-247-14.

### Git Infrastructure (verified 2026-04-30)
- 4 commits between v31.0 HEAD `cc68bfc7` and post-v31 HEAD `48554f8f`; +1 commit `acd88512` landed during this discuss-phase session — total 5 contract-touching commits in scope (one of those 5, `ad41973c`, is test-only and routes to Phase 251 per D-247-02).
- `git diff --stat cc68bfc7..acd88512 -- contracts/` → 4 files touched. Run at plan-start to confirm count + per-file insertion/deletion counts before Task 1 enumeration.
- Per-source diffs via `git show {sha} -- contracts/` (5 SHAs).
- `forge inspect contracts/storage/DegenerusGameStorage.sol:DegenerusGameStorage storage-layout` → for D-247-16 slot-layout diff (run against both `cc68bfc7` and `acd88512` SHAs).
- Working tree at start of Phase 247 execution: `contracts/ContractAddresses.sol` modified (deploy regen, ignored), `test/edge/LastPurchaseDayRace.test.js` untracked (Phase 251 scope). Plan should not stage either.

### Interface Implementer Map (for DELTA-03 call-site catalog)
- `IDegenerusGame` → implemented by `DegenerusGame.sol`; used via `IDegenerusGame(address(this))` self-calls inside modules — must enumerate both external callers and self-call sites.
- `IDegenerusVault` (if affected by `48554f8f`) → implemented by `DegenerusVault.sol`; called from `DegenerusGame.sol` + StakedDegenerusStonk where vault redemptions occur.
- `IDegenerusGameStorage` (if affected by GameStorage `+12` lines) → implemented by `DegenerusGameStorage.sol`; storage-layout-only changes typically don't require interface updates.
- Module interfaces (`IDegenerusGameMintModule`, `IDegenerusGameAdvanceModule`) → check for delegatecall selector changes from `8bdeabc2`, `6a63705b`, `acd88512`.
- Delegatecall selectors from modules use `IDegenerusGameModules` interface (43 sites verified in v27.0 `check-delegatecall-alignment.sh`); Phase 247 confirms zero delegatecall surface change in v32 deltas if classification yields no interface delta.

### Integration Points
- `audit/v32-247-DELTA-SURFACE.md` is the scope anchor for:
  - **Phase 248** (Backfill Idempotency Proof, BFL-01..06) — uses `acd88512` AdvanceModule classification rows + Consumer Index entry for `_backfillGapDays` callers
  - **Phase 249** (purchaseLevel Correctness Proof, PLV-01..06) — uses `acd88512` + `8bdeabc2` AdvanceModule classification rows + Consumer Index entry for `purchaseLevel` readsites
  - **Phase 250** (Sibling-Pattern Sweep, SIB-01..05) — uses full classification table + call-site catalog for cross-module rngLockedFlag/dailyIdx/lastPurchaseDay/jackpotPhaseFlag interactions
  - **Phase 251** (Reproduction Tests, TST-01..04) — owns test/ inventory but consumes Phase 247 contract classification for "what code is the test exercising"
  - **Phase 252** (POST31 Landed-Commit Sanity, POST31-01..02) — uses 4 commit-attributed classification subsections + storage slot diff
  - **Phase 253** (Findings Consolidation + REG, FIND-01..04 + REG-01..02) — Row IDs flow as stable citations into `audit/FINDINGS-v32.0.md` F-32-NN finding blocks
- Row IDs flow as stable citations across all downstream plan files (`248-*-PLAN.md` ... `253-*-PLAN.md`).

</code_context>

<specifics>
## Specific Ideas

- **Row ID scheme suggestion:** `D-247-C###` (changelog entries — per changed symbol), `D-247-F###` (classification entries — per function), `D-247-S###` (state/event/storage entries), `D-247-X###` (call-site cross-ref entries), `D-247-I###` (consumer index entries). Planner may flatten to single `D-247-NNN` if cleaner — must be consistent and documented in section 1 legend.
- **Reproduction recipe appendix is part of the deliverable** — not a separate file. Carries v25/v29/v30/v31 reproducibility commitment forward; reviewer can replay Phase 247 from shell.
- **Per-source "change count card"** — one-line summary per commit (e.g., "`acd88512`: 2 funcs MODIFIED_LOGIC / 0 NEW / 0 state-vars / 0 events / N new call-sites") is planner-discretion but recommended for Phase 248-252 plan-writing convenience.
- **Storage slot diff format** — `forge inspect` output before/after per slot, one row per slot-change, flagging any non-append change as a candidate for Phase 252 POST31-01 verification. The +12 lines from `48554f8f` is small enough that inline section 5 of the consolidated deliverable suffices (no companion file needed).
- **Vault refactor — heavy delta needs careful classification**: `48554f8f` `DegenerusVault.sol` is `+83/-83` net trim. Classification likely splits across multiple verdicts: REFACTOR_ONLY for hunks that just rename/relocate; MODIFIED_LOGIC for the operator-approval gate removal hunks; possibly NEW or DELETED for any helper functions added or removed. Plan should explicitly call out per-function classification for this commit (cannot lump into one row).

</specifics>

<deferred>
## Deferred Ideas

- **Automated CI gate on deltas** — wiring the catalog shape into a CI check that regenerates the classification table per PR. Out of v32.0 scope; flag as future-milestone candidate.
- **Cross-milestone delta chain audit** — tracing a function's change history across v28/v29/v30/v31/v32 catalogs. Not needed for Phase 248-252 scope.
- **Row-count bounds enforcement** — no hard floor/ceiling for Task 1's enumeration. Reconciliation via D-247-18 surfaces wildly unexpected counts; formal bounds not locked here.
- **ContractAddresses.sol audit dimension** — whether deploy-time address regeneration is itself a security surface (e.g., predictability of CREATE nonce-derived addresses) is out of v32.0 scope. Could be a future-milestone candidate if relevant.
- **test/ catalog enumeration in Phase 251** — Phase 251 will need its own catalog-shape decisions for the 5 delta-touched test/ files plus the untracked `LastPurchaseDayRace.test.js`. Defer to Phase 251 discuss-phase / plan-phase.

</deferred>

---

*Phase: 247-delta-extraction-classification*
*Context gathered: 2026-04-30*
