# Phase 132: Event Correctness - Context

**Gathered:** 2026-03-27
**Status:** Ready for planning

<domain>
## Phase Boundary

Systematic event audit across all 26 production contract files (17 top-level + 9 modules + storage). Verify every external/public state-changing function emits correct events, parameter values match actual post-state, and indexer-critical transitions are not silent. Consume and close out the 107 bot-race instances routed from Phase 130.

</domain>

<decisions>
## Implementation Decisions

### Audit Scope & Depth
- **D-01:** Full sweep of every external/public state-changing function across all 26 production files. Not limited to the bot-race findings — those are a cross-reference checklist, not the scope boundary.
- **D-02:** Three verification passes per function: (1) event exists for the state change, (2) emitted parameter values match actual post-state (no stale locals or pre-update snapshots), (3) indexer-critical transitions emit sufficient data for off-chain reconstruction.
- **D-03:** Carries from Phase 130 D-05: default disposition is DOCUMENT, not fix. No contract code changes. All findings feed Phase 134.

### Indexed Field Policy
- **D-04:** Only evaluate `indexed` fields on events that off-chain indexers need to filter by (level changes, game over, jackpot payouts, token transfers, governance actions). Ignore cosmetic `indexed` suggestions on internal bookkeeping events.
- **D-05:** The 71 NC-10/NC-33 instances from 4naly3er are triaged against this indexer-critical standard, not against "every address should be indexed."

### Output Format
- **D-06:** Single consolidated document: `audit/event-correctness.md` with sections per contract covering the fresh audit findings.
- **D-07:** Appendix in the same document maps each of the 107 routed bot findings (NC-9/10/11/17/33 + Slither DOC-02) to its disposition. Explicitly closes the Phase 130 handoff loop.

### Claude's Discretion
- Per-contract section ordering and grouping (by contract vs by finding category)
- Severity assessment per finding
- How to handle events inherited from OpenZeppelin vs custom events
- Whether to group related findings or itemize individually

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Bot-Race Findings (Phase 130 handoff)
- `audit/bot-race/4naly3er-triage.md` — Lines 419-424: five NC categories routed to Phase 132 (NC-9, NC-10, NC-11, NC-17, NC-33, ~107 instances)
- `audit/bot-race/4naly3er-report.md` — Raw 4naly3er output with per-instance locations
- `audit/bot-race/slither-triage.md` — DOC-02: events-maths (missing claimablePool event), FP-14: reentrancy-events (94 instances, all FP)

### Contract Scope (all 26 production files)
- `contracts/*.sol` — 17 top-level production contracts
- `contracts/modules/*.sol` — 9 game modules (AdvanceModule, BoonModule, DecimatorModule, DegeneretteModule, EndgameModule, GameOverModule, JackpotModule, LootboxModule, MintModule, MintStreakUtils, PayoutUtils, WhaleModule)
- `contracts/storage/DegenerusGameStorage.sol` — Shared storage with event declarations
- `contracts/libraries/*.sol` — 5 libraries (unlikely to have events but verify)
- `contracts/interfaces/*.sol` — 12 interfaces (event declarations may live here)

### Prior Audit Coverage
- `audit/v5.0-FINDINGS.md` — Master adversarial audit findings (may reference event issues)
- `audit/v7.0-findings-consolidated.md` — Delta audit of v6.0 changes

### Requirements
- `.planning/REQUIREMENTS.md` — EVT-01, EVT-02, EVT-03 definitions

</canonical_refs>

<code_context>
## Existing Code Insights

### Event Landscape
- 169 event declarations across 28 files (including mocks)
- 227 emit statements across 26 files
- Events are declared in both top-level contracts AND storage/interface files
- DegenerusGame delegatecalls to modules — events emitted in modules execute in DegenerusGame's context

### Established Patterns
- Delegatecall architecture: DegenerusGame → game modules means events emitted in modules appear as if emitted by DegenerusGame. This is correct behavior but requires tracing emit sites in module code.
- Heavy use of assembly/Yul in some contracts — verify events are emitted outside assembly blocks or correctly via `log` opcodes
- OpenZeppelin Transfer/Approval events on token contracts — these are inherited, not custom

### Integration Points
- Output: `audit/event-correctness.md` at repo root audit/ directory
- Feeds into Phase 134 KNOWN-ISSUES.md consolidation
- Bot-race appendix closes the loop on Phase 130's routed findings

</code_context>

<specifics>
## Specific Ideas

- The appendix explicitly mapping each Phase 130 bot finding to a disposition creates a clear paper trail that nothing was dropped in the handoff
- Indexer-critical standard means the audit focuses on what actually matters for production monitoring, not cosmetic best practices
- Full sweep ensures anything the bots missed (especially EVT-02 stale parameter values) gets caught

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 132-event-correctness*
*Context gathered: 2026-03-27*
