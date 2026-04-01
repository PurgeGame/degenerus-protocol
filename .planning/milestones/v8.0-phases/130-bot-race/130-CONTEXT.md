# Phase 130: Bot Race - Context

**Gathered:** 2026-03-26
**Status:** Ready for planning

<domain>
## Phase Boundary

Run Slither and 4naly3er on all production contracts. Triage every finding as fix, document (KNOWN-ISSUES.md), or false positive. The goal is to pre-empt every automated finding that C4A bots would surface on day 1 of the contest.

</domain>

<decisions>
## Implementation Decisions

### Tool Setup
- **D-01:** Claude installs 4naly3er during execution (it's a Node.js tool, git clone + run)
- **D-02:** Scope is production contracts only — 17 top-level + 5 libraries + 12 interfaces. Exclude mocks/ and test helpers.
- **D-03:** Slither 0.11.5 already installed at `/home/zak/.local/bin/slither`
- **D-04:** Run ALL Slither detectors (not just high/medium confidence) — this matches what C4A bots do. Filter noise after.

### Triage Policy
- **D-05:** Default disposition is DOCUMENT, not fix. Do not touch contract code — minimize changes this close to audit. All findings go to KNOWN-ISSUES.md.
- **D-06:** Batch all findings for review at the end. Do not escalate individual findings mid-triage, even if they look real. User reviews the full triage document and decides what (if anything) to fix in Phase 134 (Consolidation).

### Finding Disposition
- **D-07:** False positive handling and KNOWN-ISSUES.md detail level are Claude's discretion — judge per-finding whether to group (e.g., all reentrancy-benign FPs in one entry) or itemize individually.

### Claude's Discretion
- KNOWN-ISSUES.md formatting and detail level per finding
- Whether to group or itemize false positives (grouping by category vs per-function entries)
- 4naly3er detector configuration

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Existing Audit Artifacts
- `KNOWN-ISSUES.md` — Current known issues file (28 lines, needs expansion)
- `audit/v5.0-FINDINGS.md` — Master findings from ultimate adversarial audit (0 actionable, 29 INFO)
- `audit/v7.0-findings-consolidated.md` — Latest delta audit findings (3 FIXED, 4 INFO)

### Tool References
- Slither: installed at `/home/zak/.local/bin/slither`, version 0.11.5
- 4naly3er: NOT installed — needs git clone from C4A's repo during execution

### Contract Scope
- `contracts/*.sol` — 17 top-level production contracts
- `contracts/libraries/*.sol` — 5 libraries (BitPackingLib, EntropyLib, GameTimeLib, JackpotBucketLib, PriceLookupLib)
- `contracts/interfaces/*.sol` — 12 interface files
- Exclude: `contracts/mocks/`, test helpers

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- Hardhat + Foundry dual test stack (compilation already working)
- `hardhat.config.ts` — Solidity 0.8.34 configuration
- Existing `KNOWN-ISSUES.md` at repo root — extend, don't replace

### Established Patterns
- Heavy inline assembly (Yul) in several contracts — expect Slither false positives on these
- Custom storage packing — may trigger "uninitialized variable" type FPs
- Delegatecall pattern in DegenerusGame → game modules — will trigger reentrancy detectors

### Integration Points
- KNOWN-ISSUES.md at repo root is the output target
- Triage document goes in audit/ directory alongside existing audit artifacts

</code_context>

<specifics>
## Specific Ideas

- User wants to be able to tell C4A "I don't care about stuff that doesn't involve money being wrong" — KNOWN-ISSUES.md should be structured to support scoping out non-financial-impact findings
- The existing KNOWN-ISSUES.md has good structure (Intentional Design + Design Mechanics sections) but needs a new section for bot-race findings

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 130-bot-race*
*Context gathered: 2026-03-26*
