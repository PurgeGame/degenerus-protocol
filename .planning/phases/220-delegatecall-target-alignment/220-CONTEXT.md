# Phase 220: Delegatecall Target Alignment — Context

**Gathered:** 2026-04-12
**Status:** Ready for planning

<domain>
## Phase Boundary

Verify that every `<ADDR>.delegatecall(abi.encodeWithSelector(IFACE.fn.selector, ...))` and every other interface-bound `abi.encodeWithSelector(IFACE.fn.selector, ...)` use site in `contracts/` targets the address that corresponds to that interface. Produce a per-site findings document and add a static-analysis script wired into the Makefile gate so any future address/interface misalignment fails `make test`.

The bug class this phase targets: a call passes compile, the selector exists on *some* module, but the delegatecall/call target is the *wrong* module's address. The call then either reverts on unmatched selector at the target, or (worse) dispatches to a selector collision on the wrong contract. Adjacent to the `mintPackedFor` incident.

Scope boundaries:
- IN: `.delegatecall(abi.encodeWithSelector(...))`, `.call(abi.encodeWithSelector(...))`, `.staticcall(abi.encodeWithSelector(...))`, and `abi.encodeCall(IFACE.fn, args)` — all interface-bound encodings.
- OUT: Raw `bytes4(0x...)` and `bytes4(keccak256("..."))` literals — Phase 221.
- OUT: Manual `abi.encodePacked` / `abi.encode` that constructs calldata without an interface reference — Phase 221.
- OUT: Direct interface-cast external calls like `IDegenerusGame(addr).fn(...)` — already covered by `check-interface-coverage.sh` and Phase 222.

</domain>

<decisions>
## Implementation Decisions

### Script layout
- **D-01:** Create a new `scripts/check-delegatecall-alignment.sh` as a sister script to `check-interface-coverage.sh`. Each script has one narrow job.
- **D-02:** Wire the new script as a second Makefile prerequisite (alongside `check-interfaces`) so `make test-foundry` and `make test-hardhat` run both gates. Suggested target name: `check-delegatecall`. Both gates can run in parallel; failure in either blocks tests.

### Interface-to-address mapping
- **D-03:** Mapping is convention-derived: `IDegenerusGameBoonModule` ↔ `GAME_BOON_MODULE`, `IDegenerusGameJackpotModule` ↔ `GAME_JACKPOT_MODULE`, etc. Rule: strip leading `I`, replace `DegenerusGame` with empty, convert CamelCase to UPPER_SNAKE, append `_MODULE` if not already present.
- **D-04:** If a call site uses an interface or address constant that doesn't fit the convention, the script flags it as `NON_CONVENTIONAL` and requires the audit catalog (220-01-AUDIT.md) to justify it explicitly — this is a finding, not a silent pass.
- **D-05:** The script does not parse `ContractAddresses.sol` — it uses `forge inspect` + grep on call-site patterns. If the derived constant name doesn't exist in `ContractAddresses.sol`, that's a `MAPPING_ERROR` finding.

### Scope of audit (per-site coverage)
- **D-06:** Catalog covers every `abi.encodeWithSelector(IFACE.fn.selector, ...)` site (delegatecall, call, staticcall, and bare `abi.encodeCall`). Each site gets a verdict: `ALIGNED`, `MISALIGNED`, `NON_CONVENTIONAL`, `MAPPING_ERROR`, or `JUSTIFIED` (with rationale).
- **D-07:** Any `JUSTIFIED` cross-wiring (if it exists) must be explicitly listed in an allowlist file (`scripts/.delegatecall-allowlist.txt` or inline comment marker `// delegatecall-alignment: justified — <reason>`) so the regression script recognizes intentional deviations.

### Output artifacts
- **D-08:** Script prints one line per site (PASS/FAIL/WARN) to stdout, exit code 0 on clean pass.
- **D-09:** `.planning/phases/220-delegatecall-target-alignment/220-01-AUDIT.md` enumerates every site with `(file:line, caller, target_address_constant, interface_name, verdict, notes)`. Matches v25.0 audit artifact format.
- **D-10:** Findings at `HIGH`/`MEDIUM`/`LOW` severity feed into Phase 223's consolidated `audit/FINDINGS-v27.0.md`.

### Claude's Discretion
- Exact regex patterns for call-site detection (multi-line tolerance; `abi.encodeWithSelector` call can span lines — needs multiline grep or a small state machine).
- Output colorization (keep consistent with `check-interface-coverage.sh`).
- Whether to use awk, sed, or a small node.js script — script team can choose based on what keeps it under 200 lines.

</decisions>

<specifics>
## Specific Ideas

- Reference implementation pattern: `scripts/check-interface-coverage.sh` (created 2026-04-12) — same style of `forge inspect` + grep + cross-reference, same Makefile gate pattern, same PASS/FAIL/WARN stdout format.
- Prior incident that motivates this phase: `mintPackedFor` missing implementation on `DegenerusGame` (commit `a0bf328b`). Adjacent failure mode: what if the interface existed but the call used `GAME_BOON_MODULE` as target instead of the main game? The call would hit the wrong contract and revert on selector mismatch. This phase catches that.
- Known call-site catalog seen during scouting (confirmed): `DegenerusGame.sol:690` uses `GAME_LOOTBOX_MODULE` with `IDegenerusGameLootboxModule.openLootBox.selector` (aligned). `DegenerusGame.sol:782,803` use `GAME_BOON_MODULE` with `IDegenerusGameBoonModule.consume*.selector` (aligned). `DegenerusGameAdvanceModule.sol:823,862,879` use `GAME_JACKPOT_MODULE` with `IDegenerusGameJackpotModule.*.selector` (aligned). These establish the convention.

</specifics>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Prior-session artifacts (established pattern)
- `scripts/check-interface-coverage.sh` — Reference for script architecture, forge-inspect extraction, Makefile integration
- `Makefile` (target `check-interfaces`, its prerequisites `test-foundry` / `test-hardhat`) — Gate wiring pattern to mirror
- `contracts/interfaces/IDegenerusGameModules.sol` — All 9 module interfaces are defined here

### ContractAddresses mapping
- `contracts/ContractAddresses.sol` lines 11-20 — The 10 `GAME_*_MODULE` address constants that delegatecall sites target

### Example call-site patterns (confirm convention works)
- `contracts/DegenerusGame.sol:686-695` — Canonical `.delegatecall(abi.encodeWithSelector(IDegenerusGameLootboxModule.openLootBox.selector, ...))` pattern
- `contracts/modules/DegenerusGameAdvanceModule.sol:819-829` — Same pattern into `GAME_JACKPOT_MODULE`

### Requirements
- `.planning/REQUIREMENTS.md` — CSI-01, CSI-02, CSI-03 (the three requirements this phase must satisfy)

No external specs or ADRs beyond the above.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `scripts/check-interface-coverage.sh` — Pattern to mirror: forge inspect + awk for selector extraction, PASS/FAIL stdout, exit-code signaling. The MAPPINGS array concept maps directly to a call-site-verifier's alignment table.
- `Makefile` `check-interfaces` target — Wired as prerequisite to `test-foundry` and `test-hardhat`; new target can follow the same pattern.

### Established Patterns
- Module delegatecall pattern (used throughout `DegenerusGame.sol` and in every module file): `ContractAddresses.GAME_XXX_MODULE.delegatecall(abi.encodeWithSelector(IDegenerusGameXxxModule.fn.selector, args))`. The 1:1 naming correspondence is consistent across the codebase.
- `_revertDelegate(data)` helper used after failed delegatecalls in DegenerusGame to propagate the revert with original data.

### Integration Points
- Makefile `check-interfaces` target — add sibling `check-delegatecall` target and append to `test-foundry` / `test-hardhat` prereqs.
- Script output directory: `scripts/` (convention).

</code_context>

<deferred>
## Deferred Ideas

- **Storage layout regression script** — Automate what v25.0 verified manually. Different bug class (delegatecall storage corruption, not call-site misalignment). Tracked in REQUIREMENTS.md Future Requirements.
- **Deployed bytecode vs compiled source verification** — Requires RPC infrastructure. Out of v27.0 scope per decision.
- **`is IDegenerusGame` compile-time inheritance enforcement** — Explicitly deferred per session decision (~57 `override` additions too mechanical for the marginal gain over existing runtime gate).
- **Justified-cross-wiring allowlist patterns** — If no cross-wired sites are found during the audit, the allowlist file (`scripts/.delegatecall-allowlist.txt`) does not need to be created. Only materialize if JUSTIFIED findings exist.

</deferred>

---

*Phase: 220-delegatecall-target-alignment*
*Context gathered: 2026-04-12*
