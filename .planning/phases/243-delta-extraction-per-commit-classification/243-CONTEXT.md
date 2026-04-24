# Phase 243: Delta Extraction & Per-Commit Classification — Context

**Gathered:** 2026-04-23
**Status:** Ready for planning
**Mode:** Auto-decided via v29.0 Phase 230 + v30.0 Phase 237 precedents (user chose "Auto-decide via precedents")

<domain>
## Phase Boundary

Produce the authoritative v31.0 audit-surface catalog: the per-commit function-level changelog, function classification taxonomy, and downstream call-site enumeration covering the 5 post-v30.0 commits (4 code-touching + 1 docs-only) between v30.0 HEAD `7ab515fe` and current HEAD `771893d1`. Phases 244-245 consume this catalog as their sole scope input — no additional discovery required downstream.

Scope is strictly READ-only: no `contracts/` or `test/` writes. Finding-ID emission is deferred to Phase 246 (FIND-01/02/03); Phase 243 produces rows + classifications + call-site maps + Consumer Index that become the finding-candidate pool for Phase 244-245 adversarial work.

Three requirements:
- **DELTA-01** — Per-commit function / state variable / event inventory for all 5 commits with per-commit and aggregate counts, reproducible via documented `git diff` commands
- **DELTA-02** — Every changed function labeled with one of {NEW, MODIFIED_LOGIC, REFACTOR_ONLY, DELETED, RENAMED}, with diff hunks cited and hunk-level annotation attached (zero unclassified)
- **DELTA-03** — Every changed function's and interface's downstream call sites enumerated across `contracts/` via reproducible grep (zero caller unaccounted for)

</domain>

<decisions>
## Implementation Decisions

### Diff Boundary
- **D-01 (baseline = v30.0 HEAD `7ab515fe`, current = `cc68bfc7`) [AMENDED 2026-04-23 for cc68bfc7 addendum]:** Range: `7ab515fe..cc68bfc7`. 6 commits chronological: `ced654df` → `16597cac` → `6b3f4f3c` → `771893d1` → `ffced9ef` → `cc68bfc7`. Original anchor was `771893d1` (5 commits); the `cc68bfc7` commit "feat(baf): gate BAF jackpot on daily flip win" landed mid-Phase-243 execution (2026-04-23 21:25) touching 3 files in-scope (`contracts/DegenerusJackpots.sol` +19, `contracts/interfaces/IDegenerusJackpots.sol` +6, `contracts/modules/DegenerusGameAdvanceModule.sol` +22/-10). Per original D-03, the baseline reset and Phase 243 re-opened for a scope addendum. Verified: 14 files touched in `contracts/` at `7ab515fe..cc68bfc7` (`git diff --stat 7ab515fe..cc68bfc7 -- contracts/`) — original 12 + 2 new (`DegenerusJackpots.sol`, `IDegenerusJackpots.sol`); one file in the original 12 (`DegenerusGameAdvanceModule.sol`) receives additional hunks.
- **D-02 (fresh `git diff` is the single authoritative source):** Phase 243 plans derive the catalog from `git diff 7ab515fe..cc68bfc7 -- contracts/` and per-commit `git show {sha} -- contracts/`. No synthesis from commit messages, no reliance on prior catalogs — messages may be cited for CONTEXT but do not replace the diff as the source of truth (carries v29.0 Phase 230 D-02 forward).
- **D-03 (HEAD anchor locked in every plan frontmatter):** Every Phase 243 plan's frontmatter freezes `baseline=7ab515fe`, `head=cc68bfc7`. Amended from original `head=771893d1` after the `cc68bfc7` scope addendum landed mid-execution. If any FURTHER new contract commit lands before Phase 244 begins, the baseline resets again and Phase 243 re-opens for another addendum (Phase 230 D-06 / Phase 237 D-17 pattern). Phase 244 plan-start will capture the final HEAD SHA.

### Change Significance Taxonomy (DELTA-02)
- **D-04 (5-bucket classification + REFACTOR_ONLY bar):** Every changed function classified as one of {NEW, MODIFIED_LOGIC, REFACTOR_ONLY, DELETED, RENAMED}:
  - **NEW** — Function did not exist at baseline `7ab515fe`; appears at HEAD with a body.
  - **MODIFIED_LOGIC** — Function existed at baseline and HEAD; any state write, external call, control-flow branch, emitted event, or return-path evaluation changed. Removal or addition of a side-effect call (e.g., `_unlockRng(day)` removal) is MODIFIED_LOGIC.
  - **REFACTOR_ONLY** — Function existed at baseline and HEAD; source-level shape changed (whitespace, parens, local variable names, multi-line decomposition, tuple destructuring, NatSpec, parameter rename) but execution trace is byte-equivalent. Burden of proof is on REFACTOR_ONLY — any doubt escalates to MODIFIED_LOGIC.
  - **DELETED** — Function existed at baseline; absent at HEAD.
  - **RENAMED** — Same signature body at HEAD under a different name (e.g., `ethFreshWei → ethMintSpendWei` parameter rename at the call-site is RENAMED for the caller's hunk annotation, but the callee function body itself is classified by its own execution-trace delta).
- **D-05 (borderline-case rubric):** Pre-locked verdicts for known boundary cases in the 5-commit surface:
  - `16597cac` `_distributeEthGameOver` (or equivalent two-call-split continuation function): MODIFIED_LOGIC (removed `_unlockRng(day)` call is a side-effect removal).
  - `16597cac` multi-line SLOAD + tuple destructuring reformat: REFACTOR_ONLY (execution trace byte-equivalent per commit message "reformat-only").
  - `6b3f4f3c` `_callTicketPurchase`: MODIFIED_LOGIC (dropped `freshEth` return — return-path evaluation changed for every caller).
  - `6b3f4f3c` `handlePurchase` `ethFreshWei → ethMintSpendWei` parameter rename: REFACTOR_ONLY within the parameter rename hunk; MODIFIED_LOGIC where the semantics of the value passed changed (now gross spend, not fresh spend).
  - `ced654df` BAF `_jackpotTicketRoll` emit-site add: MODIFIED_LOGIC (new `emit JackpotTicketWin` is an effect).
  - `ced654df` Whale-pass fallback `_awardJackpotTickets` emit-site add: MODIFIED_LOGIC (new `emit JackpotWhalePassWin`).
  - `771893d1` MintModule/WhaleModule `gameOver` → `_livenessTriggered` gate swaps: MODIFIED_LOGIC (guard condition change is control-flow).
  - `771893d1` `sDGNRS.burn` / `burnWrapped` State-1 block: MODIFIED_LOGIC (new revert path is control-flow).
  - `771893d1` `handleGameOverDrain` `pendingRedemptionEthValue` subtraction: MODIFIED_LOGIC (arithmetic change pre-split).
  - `771893d1` `_livenessTriggered` VRF-dead 14-day grace fallback + day-math-first ordering: MODIFIED_LOGIC (new branch + ordering swap).
  - `771893d1` `_gameOverEntropy` `rngRequestTime` clearing: MODIFIED_LOGIC (new SSTORE).
  - `771893d1` `_handleGameOverPath` check ordering (gameOver before liveness): MODIFIED_LOGIC (control-flow reorder).
- **D-06 (hunk-level annotation required for every row):** Each classification row cites the exact diff hunk (file:line-range at HEAD with `+` / `-` markers or `git show {sha} -L <start>,<end>:<file>` reference) and a one-line semantic annotation. No row is "classification without citation" — every verdict traceable to source.

### Output Structure
- **D-07 (single consolidated deliverable `audit/v31-243-DELTA-SURFACE.md`):** One consolidated file matching v29.0 Phase 230 D-05 + v30.0 Phase 237 D-08 single-file pattern. Sections (planner's discretion on ordering, but all required):
  1. Per-commit changelog — function/state/event inventory grouped by commit, one row per changed symbol (DELTA-01)
  2. Aggregate function classification table — every changed function with {NEW, MODIFIED_LOGIC, REFACTOR_ONLY, DELETED, RENAMED} verdict + hunk citation (DELTA-02)
  3. Downstream call-site catalog — every changed function + changed interface method with every caller across `contracts/` tree (DELTA-03)
  4. State variable / event inventory — per-commit new/modified/deleted state variables and events, includes `DegenerusGameStorage.sol` (+27 lines) slot layout (DELTA-01 state-var coverage)
  5. Storage slot layout diff — `forge inspect` output before/after for `DegenerusGameStorage.sol` (slot-by-slot row, flagging any non-append change)
  6. Consumer Index — v31.0 requirement (EVT-01..GOE-06) → Phase 243 section/row-ID mapping (carried pattern from Phase 230 D-11 / Phase 237 D-10)
  7. Reproduction recipe appendix — all `git diff` / `git show` / `grep` / `forge inspect` commands concatenated for reviewer replay
- **D-08 (tabular, grep-friendly, no mermaid):** Carries Phase 230 D-08 / Phase 237 D-09 convention. Changelog columns: `Row ID | Commit SHA | File:Line-Range | Symbol Kind (func/state/event/interface) | Symbol Name | Change Type | One-Line Semantic Note`. Classification columns: `Row ID | Function Signature | File:Line | Classification | Hunk Ref | One-Line Rationale`. Call-site columns: `Changed Function/Interface Method | Caller File:Line | Caller Function | Call Type (direct/delegatecall/self-call) | Grep Command Used`.
- **D-09 (Row ID format — `D-243-NNN`):** Zero-padded three-digit index, e.g., `D-243-001`. Used consistently across all 7 sections so Phase 244/245 plans cite stable IDs. Suggested prefixes: `D-243-C###` (changelog), `D-243-F###` (classification/function), `D-243-S###` (state/event/storage), `D-243-X###` (call-site cross-ref), `D-243-I###` (consumer index entry). Final naming is planner's call — must be consistent and documented in section 1 legend.

### Plan Split & Wave Topology
- **D-10 (3 plans, 2-wave topology — mirrors Phase 237 D-14 exactly):**
  - `243-01-PLAN.md` DELTA-01 — Per-commit function / state / event enumeration sweep + storage slot-layout diff + reproduction recipes. Produces the universe row list.
  - `243-02-PLAN.md` DELTA-02 — Classification sweep: {NEW, MODIFIED_LOGIC, REFACTOR_ONLY, DELETED, RENAMED} verdict per function with hunk citation.
  - `243-03-PLAN.md` DELTA-03 — Call-site catalog + Consumer Index: every changed function's and interface method's downstream callers across `contracts/` via reproducible grep.
- **D-11 (wave topology — 243-01 wave 1, 243-02/243-03 wave 2 parallel):** 243-01 must commit first (universe list stabilizes scope). 243-02 and 243-03 run in parallel after 243-01 commits — each operates on the committed row list independently (classification vs call-site). Matches Phase 237 D-14 "enumeration first, then parallel" precedent.
- **D-12 (consolidation commit pattern — 243-03 writes the final `audit/v31-243-DELTA-SURFACE.md`):** 243-01 writes per-commit changelog + state/event/storage sections to a working file; 243-02 appends the classification table; 243-03 appends the call-site catalog + Consumer Index + reproduction recipe, producing the final consolidated deliverable. Final file is READ-only after 243-03 SUMMARY commit.

### Scope Boundaries
- **D-13 (ffced9ef — docs-only commit enumerated for completeness):** Commit `ffced9ef` (removal of v30.0 REQUIREMENTS.md) is enumerated as a single changelog row with `Change Type = NO_CHANGE (docs-only)`, zero symbols, zero classification rows, zero call-site rows. Appears in the 5-commit aggregate count as 1 commit / 0 functions / 0 state-vars / 0 events. Prevents the commit from being "missed" in the per-commit count audit.
- **D-14 (`contracts/` only — mocks + test + script + deploy OUT of scope):** Call-site enumeration (DELTA-03) covers `contracts/` tree only, matching Phase 230 / Phase 237 convention. `contracts/mocks/`, `contracts/test/`, `test/`, `scripts/`, `deploy/` are out of scope — they are audited contexts but not production surface. The `contracts/ContractAddresses.sol.bak` backup file seen in `ls contracts/` is NOT in the audit surface (stale per `feedback_contract_locations.md`).
- **D-15 (interface drift scope — per Phase 244 needs):** For every changed interface method in `IDegenerusGame`, `IDegenerusQuests`, `IStakedDegenerusStonk` (all three are touched by the deltas), the call-site catalog enumerates all call sites including self-calls via `IDegenerusGame(address(this))` pattern. Delegatecall selectors in `IDegenerusGameModules` interface that are impacted are also enumerated. Matches v29.0 Phase 230 D-10 interface drift pattern.
- **D-16 (storage layout diff — included in Phase 243, NOT deferred to Phase 244 GOX-07):** `DegenerusGameStorage.sol` (+27 lines) slot layout diff is produced by Phase 243 Plan 01 as part of the state variable inventory (DELTA-01 covers "state variable changed"). Phase 244 GOX-07 uses Phase 243's slot-layout diff as its sole scope input — GOX-07 verifies that the diff is backwards-compatible or explicitly intentional; producing the diff is Phase 243's job. Rationale: layout IS delta data, and keeping the `forge inspect` output in Phase 243 preserves the "sole scope input" invariant from ROADMAP phase 243 success criterion 4.

### Methodology
- **D-17 (fresh + light reconciliation):** Plan 01 enumerates FRESH via `git diff 7ab515fe..771893d1 -- contracts/` without reference to prior catalogs. Plan 01 follows with a light reconciliation pass: cross-check against v30.0 Phase 237 `audit/v30-CONSUMER-INVENTORY.md` for any RNG consumer row whose underlying function is touched by the deltas. This is a narrower reconciliation than Phase 237's full prior-artifact cross-check (D-07 there), because v30.0 is already a full-tree audit and our scope is only the deltas on top of it. Rationale: avoid Phase 237-scale reconciliation overhead when prior audit is known-complete at `7ab515fe`.
- **D-18 (grep-reproducibility mandate for DELTA-03):** Every call-site catalog row carries the exact `grep` command used to find it. Aggregate reproduction recipe appendix lists all commands (changelog `git diff`, classification `git show -L`, call-site `grep`, storage `forge inspect`) so a reviewer can replay the entire Phase 243 from shell. Commands use portable syntax (POSIX grep `-rn` with explicit path, no GNU-isms). If any `grep` produces output > 50 lines, truncate to the first 50 rows with an ellipsis annotation and keep the full output in a companion file per D-21.
- **D-19 (classification evidence burden):** Every MODIFIED_LOGIC / REFACTOR_ONLY verdict carries hunk citation AND a one-line rationale naming the specific execution-trace-changing element (SSTORE, external call, branch, emit, return-path) OR the specific non-execution-changing element (whitespace, rename, multi-line split). No hand-wave "looks like a refactor" — must name the concrete source element the verdict keys on.

### Finding-ID Emission
- **D-20 (no F-31-NN emission — Phase 246 owns it):** Phase 243 does NOT emit `F-31-NN` finding IDs. Produces rows + classifications + call-site maps that become the Phase 244/245 scope input and eventual Phase 246 finding-candidate pool. If Plan 01's fresh sweep uncovers a symbol Phase 244 plans would benefit from pre-flagging (e.g., a dropped function that no caller accounts for), it is flagged in a "Finding Candidates" subsection with file:line + proposed severity for Phase 246 routing. Carries Phase 230 D-06 / Phase 237 D-15 pattern.

### Scope-Guard Handoff
- **D-21 (Phase 243 output READ-only after 243-03 SUMMARY commit — scope-guard deferral rule):** `audit/v31-243-DELTA-SURFACE.md` and any companion files (e.g., `audit/v31-243-CALLSITES-<func>.md` if a single function's call-site grep exceeds 50 rows) are READ-only after Phase 243 closes. If Phase 244/245 finds a changed function, state-var, event, interface method, or call site NOT in the catalog, it records a scope-guard deferral in its own plan SUMMARY; Phase 243 output is not re-edited in place. Gaps become Phase 246 finding candidates. Matches Phase 230 D-06 / Phase 237 D-16 pattern.
- **D-22 (READ-only scope, no `contracts/` or `test/` writes):** Carries forward v28/v29/v30 cross-repo READ-only pattern and project-level `feedback_no_contract_commits.md` rule. Writes confined to `.planning/phases/243-*/` and `audit/v31-*` files. `KNOWN-ISSUES.md` is not touched in Phase 243 — KI promotions are Phase 246 FIND-03 only.

### Claude's Discretion
- Exact section ordering within `audit/v31-243-DELTA-SURFACE.md` (planner picks most readable of the 7 sections in D-07)
- Whether to produce a small companion "per-commit change count card" one-line summary per commit for Phase 244 plan-writing convenience
- Final Row ID prefix scheme (D-09 suggests `D-243-C/F/S/X/I-NNN` — planner may flatten to `D-243-NNN` if cleaner)
- Whether to preserve raw `git diff` output inline vs link to companion files when a single commit's diff exceeds ~200 lines
- Whether DELTA-03 call-site grep separates direct calls from delegatecall selectors in output (nice-to-have, not mandated)
- How to handle REFACTOR_ONLY function bodies that changed local-variable ordering without changing SSTORE order — recommend REFACTOR_ONLY with explicit note, but planner final call

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Milestone scope (MUST read)
- `.planning/REQUIREMENTS.md` — v31.0 requirements: DELTA-01, DELTA-02, DELTA-03 (this phase) + full catalog this phase defines the surface for (EVT/RNG/QST/GOX/SDR/GOE/FIND/REG)
- `.planning/ROADMAP.md` — Phase 243 success criteria (4 items); execution-order narrative; deliverable target `audit/v31-243-DELTA-SURFACE.md`
- `.planning/PROJECT.md` — Current Milestone section lists the 5 in-scope commits + READ-only write policy

### In-scope commits (chronological order per REQUIREMENTS.md) — 6 commits after cc68bfc7 addendum
- `ced654df` — fix(jackpot): emit accurate scaled ticketCount on all JackpotTicketWin paths (`DegenerusGameJackpotModule.sol` +33/-6)
- `16597cac` — rngunlock fix (`DegenerusGameAdvanceModule.sol` +6/-6)
- `6b3f4f3c` — feat(quests): credit recycled ETH toward MINT_ETH quests + earlybird DGNRS (`DegenerusQuests.sol`, `IDegenerusQuests.sol`, `DegenerusGameMintModule.sol`)
- `771893d1` — feat(gameover): shift purchase/claim gates to liveness + protect sDGNRS redemptions (8 files: `DegenerusGame.sol`, `StakedDegenerusStonk.sol`, `IDegenerusGame.sol`, `IStakedDegenerusStonk.sol`, `AdvanceModule`, `GameOverModule`, `MintModule`, `WhaleModule`, `DegenerusGameStorage.sol`)
- `ffced9ef` — chore: remove v30.0 REQUIREMENTS.md (docs-only; enumerated for completeness per D-13)
- `cc68bfc7` — feat(baf): gate BAF jackpot on daily flip win (`DegenerusJackpots.sol` +19, `IDegenerusJackpots.sol` +6, `DegenerusGameAdvanceModule.sol` +22/-10) — ADDENDUM COMMIT (landed 2026-04-23 21:25 mid-Phase-243 execution; re-scoped per amended D-01)

### In-scope files (14 touched in `contracts/` after cc68bfc7 addendum)
- **Top-level:** `contracts/DegenerusGame.sol`, `contracts/DegenerusQuests.sol`, `contracts/StakedDegenerusStonk.sol`, `contracts/DegenerusJackpots.sol` (added by cc68bfc7)
- **Interfaces:** `contracts/interfaces/IDegenerusGame.sol`, `contracts/interfaces/IDegenerusQuests.sol`, `contracts/interfaces/IStakedDegenerusStonk.sol`, `contracts/interfaces/IDegenerusJackpots.sol` (added by cc68bfc7)
- **Modules:** `contracts/modules/DegenerusGameAdvanceModule.sol` (receives additional hunks from cc68bfc7 beyond its 771893d1 + 16597cac + 6b3f4f3c content), `contracts/modules/DegenerusGameGameOverModule.sol`, `contracts/modules/DegenerusGameJackpotModule.sol`, `contracts/modules/DegenerusGameMintModule.sol`, `contracts/modules/DegenerusGameWhaleModule.sol`
- **Storage:** `contracts/storage/DegenerusGameStorage.sol`

### Methodology precedents (carried forward, not re-litigated)
- `.planning/milestones/v29.0-phases/230-delta-extraction-scope-map/230-CONTEXT.md` — direct precedent for single-file delta catalog, HEAD anchor, scope-guard deferral, Consumer Index; D-01/02/05/06/07/08/10/11 mirrored into D-01/02/07/08/10/11/15/21
- `.planning/milestones/v29.0-phases/230-delta-extraction-scope-map/230-01-DELTA-MAP.md` — prior single-file catalog deliverable format precedent for v31-243-DELTA-SURFACE.md shape
- `.planning/milestones/v30.0-phases/237-vrf-consumer-inventory-call-graph/237-CONTEXT.md` — direct precedent for 3-plan 2-wave topology, fresh-eyes + reconciliation, tabular grep-friendly output, no finding-ID emission; D-08/09/10/13/14/15/16/17/18 mirrored into D-07/08/09/10/11/17/20/21/22
- `.planning/milestones/v30.0-phases/237-vrf-consumer-inventory-call-graph/237-*-SUMMARY.md` — plan-close deliverable shape for Phase 243 plan summaries

### Prior audit outputs (light reconciliation per D-17)
- `audit/v30-CONSUMER-INVENTORY.md` — cross-check any RNG consumer row whose underlying function is touched by the deltas (primary D-17 target)
- `audit/FINDINGS-v30.0.md` — v30.0 findings context; any prior finding on a delta-touched function routes to Phase 246 REG-02 supersession check
- `audit/FINDINGS-v29.0.md` — v29.0 findings on delta-adjacent functions (F-29-03 MINT_ETH companion test coverage, F-29-04 gameover RNG substitution) for context on Phase 244 QST + GOX audit scope
- `audit/KNOWN-ISSUES.md` — 4 accepted RNG exceptions (affiliate roll / prevrandao fallback / F-29-04 mid-cycle substitution / EntropyLib XOR-shift); any delta that widens these re-opens Phase 244 RNG sub-audit
- `audit/STORAGE-WRITE-MAP.md` — prior storage-write catalog; `DegenerusGameStorage.sol` slot-layout diff references this for format precedent
- `audit/ACCESS-CONTROL-MATRIX.md` — prior access-control context; any new `_livenessTriggered` gate swap consults this for consistency

### Project feedback rules (apply across all plans)
- `memory/feedback_no_contract_commits.md` — READ-only scope enforcement, no `contracts/` or `test/` writes without explicit approval
- `memory/feedback_contract_locations.md` — `contracts/` is the only authoritative source; stale copies (`contracts/ContractAddresses.sol.bak`, etc.) are ignored
- `memory/feedback_no_history_in_comments.md` — deliverable docs describe what IS, not what CHANGED (except where change-tracking is the entire point, i.e., the changelog section in DELTA-SURFACE.md)

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- **Phase 230 `230-01-DELTA-MAP.md` single-file catalog format** — directly reusable for `audit/v31-243-DELTA-SURFACE.md`; same section layout (changelog / call-site / interface drift / Consumer Index)
- **Phase 237 `audit/v30-CONSUMER-INVENTORY.md` 5-section tabular structure** — reusable pattern for the 7-section Phase 243 deliverable
- **Phase 237 `237-01-PLAN.md` / `237-02-PLAN.md` / `237-03-PLAN.md` 3-plan, 2-wave split** — reusable plan topology, directly mirrored in D-10/D-11
- **Existing `audit/` deliverables** — `STORAGE-WRITE-MAP.md`, `ETH-FLOW-MAP.md`, `ACCESS-CONTROL-MATRIX.md`, `FINDINGS-v*.md`, `v30-*.md`, `v29-*.md` series — file-format precedents; `v31-*` namespace is fresh for this milestone
- **Makefile gates** — `check-interfaces`, `check-delegatecall`, `check-raw-selectors` already enforce interface↔implementation alignment; Phase 243 does NOT duplicate these gates, only catalogs the surface

### Established Patterns
- **HEAD anchor in plan frontmatter** — Phase 230 D-06 / Phase 237 D-17; applied here as D-03
- **READ-only scope on audit milestones** — v28/v29/v30 pattern; applied as D-22
- **No finding-ID emission in enumeration phases** — Phase 230 D-06 / Phase 237 D-15; applied as D-20
- **Scope-guard deferral rule** — downstream phases record deferrals instead of editing prior-phase output; applied as D-21
- **Fresh-first + reconciliation** — Phase 237 D-07 two-pass; applied as D-17 (lighter reconciliation scope since v30.0 was full-tree)
- **Single-file consolidated deliverable** — Phase 230 D-05 / Phase 237 D-08; applied as D-07
- **Tabular grep-friendly, no mermaid** — Phase 230 D-08 / Phase 237 D-09; applied as D-08

### Git Infrastructure (verified 2026-04-23)
- 5 commits present on `main` between v30.0 HEAD `7ab515fe` and current HEAD `771893d1`
- `git diff --stat 7ab515fe..771893d1 -- contracts/` → 12 files touched, 140 insertions / 57 deletions
- Per-commit diffs via `git show {sha} -- contracts/` (verified for all 4 code-touching commits)
- `git diff --name-status 7ab515fe..771893d1 -- contracts/` → per-file A/M/D status (expected all M — none A/D at surface level)
- `forge inspect contracts/storage/DegenerusGameStorage.sol:DegenerusGameStorage storage-layout` → for D-16 slot-layout diff (run against both SHAs)

### Interface Implementer Map (for DELTA-03 call-site catalog)
- `IDegenerusGame` → implemented by `DegenerusGame.sol`; used via `IDegenerusGame(address(this))` self-calls inside modules (Advance, GameOver, Jackpot, Mint, Whale) — must enumerate both external callers and self-call sites
- `IDegenerusQuests` → implemented by `DegenerusQuests.sol`; called from modules via the quests address getter
- `IStakedDegenerusStonk` → implemented by `StakedDegenerusStonk.sol`; called from `DegenerusGame.sol` + modules where sDGNRS operations occur
- Delegatecall selectors from modules use `IDegenerusGameModules` interface for selector reference (43 sites verified in v27.0 `check-delegatecall-alignment.sh`)

### Integration Points
- `audit/v31-243-DELTA-SURFACE.md` is the scope anchor for:
  - **Phase 244** (per-commit adversarial audit) — EVT/RNG/QST/GOX plans consume classification rows + call-site catalog as their scope input
  - **Phase 245** (sDGNRS + gameover safety) — SDR/GOE plans use the `771893d1`-delta classification rows + `DegenerusGameStorage.sol` slot-layout diff as their primary scope
  - **Phase 246** (findings consolidation) — Row IDs flow as stable citations into `audit/FINDINGS-v31.0.md` F-31-NN finding blocks
- Row IDs flow as stable citations across all downstream plan files (`244-*-AUDIT.md`, `245-*-AUDIT.md`, `246-*`)

</code_context>

<specifics>
## Specific Ideas

- **Row ID scheme suggestion:** `D-243-C###` (changelog entries — per changed symbol), `D-243-F###` (classification entries — per function), `D-243-S###` (state/event/storage entries), `D-243-X###` (call-site cross-ref entries), `D-243-I###` (consumer index entries). Planner may flatten to single `D-243-NNN` if cleaner — must be consistent and documented in section 1 legend.
- **Reproduction recipe appendix is part of the deliverable** — not a separate file. Carries v25/v29/v30 reproducibility commitment forward; reviewer can replay the entire Phase 243 from shell.
- **Per-commit "change count card"** — one-line summary per commit (e.g., "`ced654df`: 4 funcs MODIFIED_LOGIC / 2 NEW events / 0 state-vars / 11 new call-sites") is planner-discretion but recommended for Phase 244 plan-writing convenience.
- **Storage slot diff format** — `forge inspect` output before/after per slot, one row per slot-change, flagging any non-append change as a candidate for Phase 244 GOX-07 verification. Recommend using a companion file `audit/v31-243-STORAGE-LAYOUT-DIFF.md` only if the slot count > 30; otherwise inline in section 5 of the consolidated deliverable.

</specifics>

<deferred>
## Deferred Ideas

- **Automated CI gate on deltas** — wiring the catalog shape into a CI check (e.g., a script that regenerates the classification table per PR). Out of v31.0 scope (READ-only); flag as future-milestone candidate.
- **Cross-milestone delta chain audit** — tracing a function's change history across v28/v29/v30/v31 catalogs. Not needed for Phase 244/245 scope; could be a future audit convenience tooling item.
- **Row-count bounds enforcement** — no hard floor/ceiling set for Plan 01's enumeration. If the fresh sweep produces a wildly unexpected count (e.g., 0 rows or 1000+ rows), reconciliation via D-17 would surface it; formal bounds not locked here.

</deferred>

---

*Phase: 243-delta-extraction-per-commit-classification*
*Context gathered: 2026-04-23*
