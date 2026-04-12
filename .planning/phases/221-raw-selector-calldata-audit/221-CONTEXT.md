# Phase 221: Raw Selector & Calldata Audit — Context

**Gathered:** 2026-04-12
**Status:** Ready for planning

<domain>
## Phase Boundary

Catalog every non-interface-bound calldata construction site in `contracts/` and assign each a severity verdict, then install a regression gate that prevents future raw-selector drift.

**In scope:**
- Every `bytes4(0x...)` hex literal in `contracts/` (CSI-04)
- Every `bytes4(keccak256("..."))` string-derived selector in `contracts/` (CSI-05)
- Every `abi.encode` / `abi.encodeCall` / `abi.encodeWithSignature` site that **constructs calldata** passed to `.call` / `.delegatecall` / `.staticcall` / `transferAndCall` without an `IXxx.fn.selector` reference (CSI-06)
- Catalog artifact feeding Phase 223 findings (CSI-07)

**Out of scope:**
- `abi.encode*` whose output feeds `keccak256(...)` (hash-salt construction, not calldata) — 40+ sites in the codebase, none selector-bearing
- `abi.encode*` whose output constructs strings for NFT metadata / JSON (DegenerusDeityPass, DegenerusAffiliate `tokenURI` paths) — not calldata
- `abi.encodeWithSelector(IXxx.fn.selector, ...)` — already audited in Phase 220 (interface-bound, aligned)
- Direct interface-cast external calls `IXxx(addr).fn(...)` — covered by `check-interface-coverage.sh`

**Bug class this phase targets:** A selector or calldata literal that compiles, matches some function on some contract, but drifts away from its referent over time (renamed function, dropped argument, changed module) — same class as `mintPackedFor` except via raw selector instead of missing implementation.

</domain>

<decisions>
## Implementation Decisions

### Gate script (following Phase 220 precedent)
- **D-01:** Create `scripts/check-raw-selectors.sh` as a sister script to `check-delegatecall-alignment.sh` and `check-interface-coverage.sh`. One narrow job per script.
- **D-02:** Wire as a Makefile prerequisite (e.g., `check-raw-selectors` target) alongside the existing `check-interfaces` and `check-delegatecall` prerequisites of `test-foundry` and `test-hardhat`. Failure blocks tests.
- **D-03:** Gate scans `contracts/` but excludes `contracts/mocks/` via path filter. Mock contracts legitimately use `abi.encodeWithSignature` to mimic Chainlink VRF v2 wire format.
- **D-04:** Gate must exit 0 on clean pass, exit 1 on any FLAGGED site or any `bytes4(0x...)` / `bytes4(keccak256(...))` / `abi.encodeWithSignature` / `abi.encodeCall` appearance in production contracts. It should print one PASS/FAIL/WARN line per site for quick triage. Pattern mirrors `check-delegatecall-alignment.sh`.

### Classification scope — what gets a verdict
- **D-05:** Only `abi.encode*` sites whose output is passed as the **calldata argument** to `.call` / `.delegatecall` / `.staticcall` / `transferAndCall` / low-level `send` are classified. Hash-input and string-building uses of `abi.encode*` are explicitly out of scope (they are not selectors).
- **D-06:** Any `bytes4(0x...)` or `bytes4(keccak256("..."))` found in production contracts (outside `contracts/mocks/`) is classified — regardless of whether it flows into a call. Raw selector literals anywhere in production are an audit target, even if only used in assembly or as a sentinel.
- **D-07:** Every classified site receives one of four verdicts in the catalog table: `JUSTIFIED` (raw form is required — e.g., interface for the target doesn't exist in this repo, like Chainlink external coordinator), `REPLACED` (changed in place to interface-bound form), `FLAGGED` (finding — feeds Phase 223), or `DOCUMENTED` (no code change, kept as-is with rationale).

### Mocks handling
- **D-08:** The 3 `abi.encodeWithSignature` sites in `contracts/mocks/` (MockVRFCoordinator lines 88, 111; MockLinkToken line 51) are listed in the catalog with `JUSTIFIED` verdict. Justification: they simulate Chainlink v2 coordinator wire format (`rawFulfillRandomWords(uint256,uint256[])`) that the real coordinator sends to `VRFConsumerBaseV2`. The interface target is external to the repo.
- **D-09:** The gate script path-excludes `contracts/mocks/` so these sites do not cause `make test` to fail, but the audit catalog still enumerates them for completeness. If future mocks add raw selectors for a different external dependency, they inherit `JUSTIFIED` (documented) treatment.

### Output artifacts
- **D-10:** Produce a single `221-01-AUDIT.md` in the phase directory (matches Phase 220 style). Sections: CSI-04 hex literals, CSI-05 string selectors, CSI-06 calldata constructors, CSI-07 verdict summary. Empty sections collapse to "0 sites surveyed, requirement SATISFIED" with the grep command that produced the empty result — proves absence rather than hiding it.
- **D-11:** Each catalog row: `(file:line, construct, target_context, verdict, severity, notes)`. `construct` = `bytes4_hex` / `bytes4_keccak` / `abi.encodeWithSignature` / `abi.encodeCall` / `abi.encode` / `abi.encodePacked`. `target_context` = the `.call`/`.delegatecall`/etc receiver (or "hash-salt" / "string-concat" / "external-chainlink" for non-call flows in the sanity sweep).

### Severity calibration (for Phase 223 rollup)
- **D-12:** Any `FLAGGED` site (no justification possible, raw selector or calldata bypass in production): severity `HIGH` — same class as `mintPackedFor` (CSI-01 precedent) because a runtime mismatch is exactly the bug that motivated v27.0.
- **D-13:** Brittleness-only findings (e.g., a raw selector that happens to be correct today but has no compile-time tether to its referent): severity `MEDIUM`. `DOCUMENTED` sites kept for external-contract compatibility: `INFO`.
- **D-14:** Expected baseline per scout: 0 `FLAGGED`, 3 `JUSTIFIED` (Chainlink mocks), 0 `REPLACED`, 0 `DOCUMENTED`. If scouting is confirmed during execution, CSI-04 / CSI-05 / CSI-06 all satisfy-by-absence with the regression gate locking it in.

### Claude's Discretion
- Exact regex patterns for selector detection (multi-line tolerance for `abi.encode*` that wraps arguments)
- Script language choice (bash/awk vs. small node.js script) — keep under 200 lines, follow Phase 220's style (bash + awk pattern established there)
- Output colorization — match `check-delegatecall-alignment.sh`
- Whether to emit a JSON sidecar for CI tooling — optional; not required unless planner sees a need

### Folded Todos
None — backlog had no matches for this phase.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Requirements
- `.planning/REQUIREMENTS.md` §v27.0 CSI-04 through CSI-07 — what this phase must satisfy
- `.planning/PROJECT.md` — v27.0 milestone goal: prevent mintPackedFor-class runtime mismatches

### Prior-phase artifacts (patterns to mirror)
- `.planning/phases/220-delegatecall-target-alignment/220-CONTEXT.md` — prior-phase decisions on script layout, gate wiring, catalog format
- `.planning/phases/220-delegatecall-target-alignment/220-01-AUDIT.md` — reference catalog format (verdict table, severity columns)
- `.planning/phases/220-delegatecall-target-alignment/220-VERIFICATION.md` — phase-verification template
- `scripts/check-delegatecall-alignment.sh` — script architecture reference (forge-inspect + awk + Makefile integration)
- `scripts/check-interface-coverage.sh` — original pattern
- `Makefile` — gate wiring (`check-interfaces`, `check-delegatecall` → prerequisites of `test-foundry` / `test-hardhat`); add `check-raw-selectors` as sibling

### In-scope code surfaces (confirmed by scout)
- `contracts/mocks/MockVRFCoordinator.sol:88,111` — `abi.encodeWithSignature("rawFulfillRandomWords(uint256,uint256[])", ...)` — JUSTIFIED candidate
- `contracts/mocks/MockLinkToken.sol:51` — `abi.encodeWithSignature(...)` — JUSTIFIED candidate
- `contracts/DegenerusAdmin.sol:914,997` — `abi.encode(newSubId)` / `abi.encode(subId)` passed to `linkToken.transferAndCall` — CSI-06 classification target (Chainlink external encoding; verdict likely JUSTIFIED)

### Background
- commit `a0bf328b` — `mintPackedFor` fix (the incident v27.0 prevents the next version of)
- commit `23bbd671` — `check-interfaces` Makefile gate introduction

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `scripts/check-delegatecall-alignment.sh` (Phase 220) — **direct pattern to clone.** Forge-inspect extraction, awk-based call-site scan, PASS/FAIL stdout, mapping validation. CSI-03 precedent proves this architecture works at ~sub-1s runtime vs ~10s for `check-interfaces`.
- `scripts/check-interface-coverage.sh` — original pattern; still referenced for forge-inspect idioms
- `Makefile` `check-interfaces` / `check-delegatecall` targets — gate wiring template

### Established Patterns
- **Convention-derived validation** (from Phase 220): prefer rules that derive expected form mechanically from existing code (e.g., strip `I` prefix, CamelCase → UPPER_SNAKE) over hand-maintained tables. Applied here: a raw selector site either resolves to a known interface function (`IXxx.fn.selector`) or it's FLAGGED.
- **Allowlist via explicit constant**, not inline comment (from Phase 220 D-05): mocks/ gets a path-level exclusion, not a comment-based one — visible in the script diff, impossible to accidentally add without a code review noticing.
- **Preflight-then-per-site gate architecture** (Phase 220-02): universe-level validation runs first with a clear error message; per-site pass/fail only meaningful if universe is well-formed. Apply here: if any `bytes4(0x...)` / `bytes4(keccak256(...))` / `abi.encodeCall` / `abi.encodeWithSignature` appears in production, universe is bad and gate fails fast.

### Integration Points
- Makefile: new `check-raw-selectors` target becomes a sibling prerequisite of `test-foundry` / `test-hardhat` (alongside `check-interfaces`, `check-delegatecall`)
- Script output: `scripts/` directory (same as Phase 220)
- Catalog output: `.planning/phases/221-raw-selector-calldata-audit/221-01-AUDIT.md`

### Files the gate must NOT touch
- `contracts/*.sol` production contracts (feedback_no_contract_commits)
- `test/**` Foundry test files
- `ContractAddresses.sol` is modifiable per `feedback_contractaddresses_policy.md` — but not expected to change in Phase 221

</code_context>

<specifics>
## Specific Ideas

- **Empty-catalog framing:** `221-01-AUDIT.md` section headers should read "CSI-04: Hex literal selectors — 0 sites (SATISFIED)" with the exact grep command used to prove absence, so a reader can re-run and confirm. Don't leave empty sections looking like they were skipped.
- **Script naming:** `scripts/check-raw-selectors.sh` (not `check-selectors.sh` — "raw" distinguishes it from Phase 220's interface-bound selector gate).
- **What a future regression looks like:** someone writes `address(foo).call(abi.encodeWithSignature("transfer(address,uint256)", to, amt))` when they could have used `IERC20(foo).transfer(to, amt)`. The gate flags `abi.encodeWithSignature` presence in production and fails `make test`. Catch-and-fail before commit, not during audit.

</specifics>

<deferred>
## Deferred Ideas

- **`is IXxx` compile-time inheritance** — same decision as Phase 220; mechanical cost too high vs runtime gate. Already in REQUIREMENTS.md Out of Scope.
- **Deployed bytecode vs source verification** — out of v27.0 milestone scope; requires RPC infra.
- **Revert specificity (`E()` → custom errors)** — improves debuggability, not correctness; tracked in REQUIREMENTS.md Future Requirements.

### Reviewed Todos (not folded)
None — `todo match-phase 221` returned 0 matches.

</deferred>

---

*Phase: 221-raw-selector-calldata-audit*
*Context gathered: 2026-04-12*
