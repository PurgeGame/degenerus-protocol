# Phase 222: External Function Coverage Gap — Context

**Gathered:** 2026-04-12
**Status:** Ready for planning

<domain>
## Phase Boundary

Every external/public function on a deployed contract is classified as COVERED / CRITICAL_GAP / EXEMPT, every CRITICAL_GAP has ≥1 new test exercising it on a realistic path, and the `test/fuzz/FuturepoolSkim.t.sol` compile error is fixed so `forge coverage` runs to completion. A `make coverage-check` target enforces the classification threshold on future changes.

**In scope:**
- Fix `FuturepoolSkim.t.sol` compile error (CSI-08) — references `_applyTimeBasedFutureTake` which was inlined into `_consolidatePoolsAndRewardJackpots` during v20.0 (commit d8dbd9e3)
- Run `forge coverage --report summary` (and lcov for branch data) across every deployed contract (CSI-09)
- Produce classification matrix with COVERED / CRITICAL_GAP / EXEMPT verdict per external/public function (CSI-10)
- Add ≥1 new test per CRITICAL_GAP that exercises the function on a realistic path (CSI-11)
- Add `make coverage-check` threshold gate as a standalone target (not wired into `test-foundry` — `forge coverage` is too slow per-build)

**Out of scope:**
- Internal/private functions (not reachable via external call — different risk class)
- Libraries (`BitPackingLib`, `EntropyLib`, `GameTimeLib`, `JackpotBucketLib`, `PriceLookupLib`) — tested through their callers, not deployed as own address
- `contracts/interfaces/` — declarations only
- `contracts/storage/` — abstract base, no deployable external surface
- `contracts/mocks/` — test-only deployables; coverage not relevant
- Performance/gas tuning of new tests
- Storage layout or bytecode verification (Future Requirements, not v27.0)

**Bug class this phase targets:** mintPackedFor-class — an external/public function exists on a deployed contract but is never invoked by any test, so a silent revert on a conditional entry point (threshold crossing, specific state) can hide through compile and superficial testing and only surface at runtime. Coverage = proof of reachability under test.

</domain>

<decisions>
## Implementation Decisions

### CSI-08 — FuturepoolSkim.t.sol fix approach
- **D-01:** Rewrite the 8+ fuzz tests to exercise `_consolidatePoolsAndRewardJackpots` end-to-end rather than the removed `_applyTimeBasedFutureTake`. Tests reach the skim block through the real consolidation function.
- **D-02:** Accept broader test scope — each test exercises the full pipeline (time-based skim, coinflip credit, BAF/Decimator triggers, future→next drawdown). Assertions verify skim outputs AND side-effect invariants together. No isolation via zeroed inputs, no splitting into two files.
- **D-03:** `SkimHarness` extends `DegenerusGameAdvanceModule` and exposes accessors via `exposed_*` methods (existing pattern) for the rewritten invocation. No changes to `contracts/modules/DegenerusGameAdvanceModule.sol` (no private-function extraction).

### CSI-09 — Coverage run scope
- **D-04:** Run `forge coverage --report summary` for the headline metric (CSI-09 literal wording) AND `forge coverage --report lcov` for per-branch data (needed for CSI-10 branch-coverage gating). Both reports produced in the same invocation.
- **D-05:** Scope = every `.sol` file in `contracts/` that deploys as its own address. Concretely:
  - 17 top-level candidates in `contracts/*.sol` — researcher/planner MUST filter libraries/data-only files (`ContractAddresses.sol`, `DegenerusTraitUtils.sol` if library, `Icons32Data.sol`) from the classification universe; deployable set is a subset of 17
  - 11 modules in `contracts/modules/*.sol` (delegatecall targets, each deploys as own address)
  - Excluded: `contracts/interfaces/` (declarations), `contracts/libraries/` (linked, not standalone), `contracts/storage/` (abstract base), `contracts/mocks/` (test-only)
- **D-06:** REQUIREMENTS.md lists 10 explicit targets (DegenerusGame, modules, BurnieCoin, BurnieCoinflip, Affiliate, Jackpots, Quests, sDGNRS, Vault, Stonk). User widened scope to include **all deployable .sol** — so DegenerusAdmin, DegenerusDeityPass, DeityBoonViewer, GNRUS, WrappedWrappedXRP are IN SCOPE and classified alongside the original 10.

### CSI-10 — Classification taxonomy

**COVERED** — function qualifies when BOTH conditions hold:
- **D-07:** ≥1 test invocation (direct or via handler chain) AND
- **D-08:** ≥50% branch coverage per `forge coverage --report lcov` on that function's bytecode

  Rationale: invocation alone does not catch mintPackedFor-class. That bug's function was reachable but the reverting conditional branch was never entered. Branch coverage at 50% is the minimum threshold that forces at least one conditional path to be exercised. Happy-path-only functions (no conditionals — trivial setters/getters) pass automatically because branch coverage of a branch-free function is 100% by definition.

**CRITICAL_GAP** — function qualifies when:
- **D-09:** Function is external or public on a deployed contract AND is NOT auto-exempt AND fails the COVERED threshold (either no invocation OR invocation without ≥50% branch coverage)
- **D-10:** Broad definition (no severity sub-classification). Every uncovered non-exempt function is CRITICAL_GAP. Rationale: user requirement "all functions must work, never bug out" — narrower definitions leave holes.

**EXEMPT** — function auto-exempt from coverage requirement when it matches ANY of:
- **D-11:** `view` or `pure` (no state change — silent revert self-evident at call site; trivially detectable in review)
- **D-12:** External-callback target (VRF `rawFulfillRandomWords`, LINK ERC-677 `onTokenTransfer`, `fallback`, `receive`) — called only by trusted external contracts with their own test coverage

  **NOT auto-exempt** (must still pass COVERED — no blanket exemption):
  - Admin-gated (`onlyOwner`, `onlyAdmin`) — user explicitly rejected this exemption; admin paths can still hide mintPackedFor-class bugs
  - Governance-gated — same reason
  - Emergency/pause-gated — same reason

### CSI-11 — CRITICAL_GAP test depth
- **D-13:** Each new test reaches the CRITICAL_GAP function through its **natural caller chain** (integration style). Example: a `DegenerusQuests._isLevelQuestEligible` gap test drives `purchaseX()` which triggers quest eligibility mid-flow, not a direct handler-test call. Matches where mintPackedFor's bug actually hid.
- **D-14:** State-changing CRITICAL_GAPs must exercise the **conditional-entry branch** — the test must make the `if`/`require`/conditional dispatch take the non-trivial branch. Verified via `forge coverage --report lcov` showing branch-hit on the target line. Trivial setters (no conditionals) pass with happy-path only.
- **D-15:** Reuse existing handlers in `test/fuzz/handlers/` and integration harnesses where one covers the target surface. Build a fresh test file only when no existing handler exposes the function. Consistent with the established fuzz architecture.

### Deliverables shape
- **D-16:** Ship `make coverage-check` as a **standalone Makefile target** — NOT a prerequisite of `test-foundry` / `test-hardhat` (forge coverage is minutes-long; not suitable for per-build execution). Runs manually and in CI. Target produces PASS on classification-matrix compliance (no uncategorized externals, no CRITICAL_GAPs without linked tests), FAIL otherwise.
- **D-17:** Produce classification matrix as `222-01-COVERAGE-MATRIX.md` (or `222-01-AUDIT.md` — planner's choice; Phase 220/221 naming precedent is `-01-AUDIT.md`). Per-function row: `(contract, function_signature, visibility, verdict, rationale, test_ref)`. Sections by contract. Feeds Phase 223 rollup.
- **D-18:** `coverage-check` implementation mirrors the Phase 220/221 pattern — bash + awk script under `scripts/`, one narrow job (compare classification matrix against `forge coverage` output, report drift). Does NOT invoke forge coverage itself; consumes a cached lcov report. Entry point for the slow coverage run is documented separately.

### Claude's Discretion
- Exact numeric ordering of the matrix (by contract? by verdict severity? by function name?)
- Whether classification matrix is one file or per-contract files under a directory
- Choice of fuzz runs/depth settings for new integration tests (match existing conventions in `foundry.toml`)
- Format of `coverage-check` script output (colorized? JSON sidecar? plain PASS/FAIL lines)
- Whether to produce a companion `222-02-REGRESSION.md` summarizing which existing test files grew vs. which are new
- How to present CRITICAL_GAP priorities (rank by call-site count? by module criticality? by blast radius?)

### Folded Todos
None — `todo match-phase 222` returned 0 matches.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Requirements & project context
- `.planning/REQUIREMENTS.md` §v27.0 CSI-08 through CSI-11 — what this phase must satisfy
- `.planning/PROJECT.md` — v27.0 milestone goal: prevent mintPackedFor-class runtime mismatches

### Prior-phase artifacts (patterns to mirror)
- `.planning/phases/220-delegatecall-target-alignment/220-CONTEXT.md` — gate architecture, Makefile wiring, artifact naming
- `.planning/phases/220-delegatecall-target-alignment/220-01-AUDIT.md` — catalog format (per-site verdict table)
- `.planning/phases/220-delegatecall-target-alignment/220-VERIFICATION.md` — phase-verification template
- `.planning/phases/221-raw-selector-calldata-audit/221-CONTEXT.md` — most recent precedent; decisions on `contracts/mocks/` exclusion, `SATISFIED BY ABSENCE` framing, per-site rows
- `.planning/phases/221-raw-selector-calldata-audit/221-01-AUDIT.md` — audit document format for a "satisfied by absence" case
- `scripts/check-delegatecall-alignment.sh` — script architecture reference (bash + awk, CONTRACTS_DIR override)
- `scripts/check-raw-selectors.sh` — most recent sibling pattern (221-01); coverage-check script should parallel its structure
- `Makefile` — gate wiring (`check-interfaces`, `check-delegatecall`, `check-raw-selectors` → prerequisites of `test-foundry` / `test-hardhat`); `coverage-check` is a DIFFERENT category (standalone target, not a prereq)

### In-scope code surfaces — CSI-08 fix
- `test/fuzz/FuturepoolSkim.t.sol` (blocker) — 8+ fuzz tests referencing removed `_applyTimeBasedFutureTake` and removed helpers
- `contracts/modules/DegenerusGameAdvanceModule.sol:630` — `_consolidatePoolsAndRewardJackpots` (target of rewrite)
- `contracts/modules/DegenerusGameAdvanceModule.sol:1241` — `_nextToFutureBps` (still exists, used by the skim block inside consolidation)
- commit `d8dbd9e3` (v20.0 Phase 186) — consolidation refactor that inlined `_applyTimeBasedFutureTake`
- commit `58465a7f` — original skim design and FuturepoolSkim.t.sol introduction

### Classification universe — deployed contract inventory
- `contracts/DegenerusGame.sol` (original 10)
- `contracts/BurnieCoin.sol` (original 10)
- `contracts/BurnieCoinflip.sol` (original 10)
- `contracts/DegenerusAffiliate.sol` (original 10)
- `contracts/DegenerusJackpots.sol` (original 10)
- `contracts/DegenerusQuests.sol` (original 10)
- `contracts/StakedDegenerusStonk.sol` (original 10)
- `contracts/DegenerusVault.sol` (original 10)
- `contracts/DegenerusStonk.sol` (original 10)
- `contracts/DegenerusAdmin.sol` (**added via D-06**)
- `contracts/DegenerusDeityPass.sol` (**added via D-06**)
- `contracts/DeityBoonViewer.sol` (**added via D-06**)
- `contracts/GNRUS.sol` (**added via D-06** — researcher should confirm deploys standalone)
- `contracts/WrappedWrappedXRP.sol` (**added via D-06**)
- `contracts/modules/*.sol` — all 11 modules (original "modules" in the 10-list)
- **Exclude (probably libraries/data, verify):** `contracts/ContractAddresses.sol`, `contracts/DegenerusTraitUtils.sol`, `contracts/Icons32Data.sol`

### Coverage tooling
- `foundry.toml` — existing coverage config (check `[profile.default]`); may need `via_ir = false` for accurate coverage per Foundry docs
- `forge coverage --report summary` — CSI-09 headline
- `forge coverage --report lcov` — branch-coverage source for CSI-10 threshold (D-08)
- Existing CI integrations (`.github/workflows/*`) — if present, coverage-check target needs wiring

### Background
- commit `a0bf328b` — mintPackedFor fix (the incident v27.0 prevents the next version of)
- commit `23bbd671` — `check-interfaces` Makefile gate introduction
- Phase 220/221 INFO findings — feed into CRITICAL_GAP prioritization (unexercised surface flagged by earlier phases should be tested first)

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- **`test/fuzz/handlers/*`** — existing fuzz handler contracts for per-contract test composition. CRITICAL_GAP tests should extend or reuse these handlers (D-15) rather than bypassing them.
- **`test/fuzz/helpers/*`** — shared test setup utilities (protocol deploy, token mint, VRF plumbing). Reuse before writing new deploy scaffolding.
- **`test/integration/*`** — end-to-end integration harness; natural home for CRITICAL_GAP tests that reach functions through `purchase*` / `advanceGame` / `redeem*` flows (D-13).
- **`SkimHarness` pattern** (test/fuzz/FuturepoolSkim.t.sol) — `exposed_*` method convention for testing private functions via a test-only subclass.
- **`scripts/check-delegatecall-alignment.sh` / `scripts/check-raw-selectors.sh`** — bash + awk + CONTRACTS_DIR override pattern for the new `scripts/coverage-check.sh`.
- **`forge coverage` infrastructure** — already wired in Foundry; blocker is CSI-08 compile error, not tooling absence.

### Established Patterns
- **Gate + audit artifact** (from 220/221): each call-site-integrity phase ships a Makefile gate AND an audit document. Phase 222 splits: gate is `coverage-check` (standalone, not a per-build prereq); audit is `222-01-COVERAGE-MATRIX.md`.
- **`contracts/mocks/` path exclusion** (from 221 D-03): mirror for `coverage-check` — exclude mocks from classification universe.
- **CONTRACTS_DIR env override** (from 220-01): any new script must support this to let negative tests run against fixtures in /tmp without touching `contracts/`.
- **Preflight-then-per-site** (from 220-02): validate classification matrix structure BEFORE per-function comparison so universe-level drift fails fast with a clear error.
- **`exposed_*` harness methods** (test/fuzz/): test private behavior via a subclass, not via contract edits — applies directly to CSI-08 fix.

### Integration Points
- **Makefile**: new `coverage-check` target (standalone, NOT in `test-foundry` prereqs)
- **`scripts/`**: new `scripts/coverage-check.sh` — bash + awk, sibling of `check-raw-selectors.sh`
- **Phase dir**: classification matrix lives at `.planning/phases/222-external-function-coverage-gap/222-01-COVERAGE-MATRIX.md` (or `-AUDIT.md` per 220/221)
- **`test/` surface**: rewritten `FuturepoolSkim.t.sol` + new test files for CRITICAL_GAPs (under `test/fuzz/` or `test/integration/`)
- **Phase 223 feed**: CRITICAL_GAP rows with severity and remediation status → consolidated findings document

### Files the phase must NOT touch
- `contracts/*.sol` production contracts — requires explicit user approval per `feedback_no_contract_commits.md`. D-03 commits to NOT extracting `_applyTimeBasedFutureTake` back to a private function, so no contracts/ edits are expected. If ANY contract edit is discovered necessary during execution, STOP and request approval.
- `contracts/mocks/*` — test-only; out of classification universe
- `ContractAddresses.sol` — modifiable per `feedback_contractaddresses_policy.md` (not expected to change here, but permitted if needed for deploy predictability)

</code_context>

<specifics>
## Specific Ideas

- **Classification matrix format:** Per-contract sections, per-function rows. Columns: `Contract | Function | Visibility | Verdict | Branch Cov | Test Ref | Notes`. EXEMPT entries carry their exemption rationale in Notes (e.g., "view", "VRF callback", "ERC-677 callback"). CRITICAL_GAP entries carry the planned test reference in Test Ref (file:line once tests land).
- **`coverage-check` failure semantics:** Three failure modes — (a) external/public function present on deployed contract but MISSING from matrix → FAIL (universe drift); (b) function classified CRITICAL_GAP but no test_ref linked → FAIL (uncured gap); (c) function classified COVERED but `forge coverage` shows branch <50% → FAIL (regressed coverage). Exit 0 only when all three pass.
- **Evidence recipe for CSI-09:** Commit `forge coverage --report summary` output alongside the matrix. A future auditor should be able to re-run `forge coverage` and obtain the same numbers, or else explain the divergence.
- **What a future regression looks like:** Someone adds an external function on DegenerusGame without adding a test. `make coverage-check` fails on universe drift. They must either add the test (COVERED) or classify EXEMPT with justification. Catches mintPackedFor-class at PR time, not at audit time.
- **CSI-08 specific rewrite shape:** Each existing `test_X` in `FuturepoolSkim.t.sol` needs its setup expanded so `_consolidatePoolsAndRewardJackpots` runs cleanly — that means initializing coinflip pools, BAF/Decimator state, future/next pool values, level state. Reuse helper from `test/fuzz/helpers/` if one exists; add one if not. Assertions expand to include side-effect invariants (coinflip pool deltas, BAF trigger absence on non-BAF scenarios, future→next drawdown correctness).

</specifics>

<deferred>
## Deferred Ideas

- **Extract `_applyTimeBasedFutureTake` back to a private function** — rejected; reverses a v20.0 consolidation decision with no compensating benefit. User picked rewrite-against-parent.
- **CI wall-clock budget for `coverage-check`** — out of scope here; if CI timing becomes a problem, follow-up milestone can split coverage into layers.
- **Per-function coverage targets above 50%** — tighter branch-coverage thresholds may be warranted for specific high-risk functions but would require per-function tuning. Kept at uniform 50% for this milestone; revisit if Phase 222 discovers specific hot spots.
- **Deployed bytecode verification** — already in REQUIREMENTS.md Future Requirements; not v27.0 scope.
- **Revert specificity (`E()` → custom errors)** — already in REQUIREMENTS.md Future Requirements; different risk class from coverage.
- **`is IXxx` compile-time interface inheritance** — already decided in Phase 220/221 CONTEXTs; mechanical cost too high vs. runtime gate.

### Reviewed Todos (not folded)
None — `todo match-phase 222` returned 0 matches.

</deferred>

---

*Phase: 222-external-function-coverage-gap*
*Context gathered: 2026-04-12*
