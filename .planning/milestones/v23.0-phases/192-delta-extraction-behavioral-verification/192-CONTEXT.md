# Phase 192: Delta Extraction & Behavioral Verification - Context

**Gathered:** 2026-04-06
**Status:** Ready for planning

<domain>
## Phase Boundary

Extract function-level diffs from commits 93c05869 and 520249a2, classify each change as refactor or intentional behavioral change, and prove correctness for all paths. No code changes -- audit only.

</domain>

<decisions>
## Implementation Decisions

### Audit Methodology
- **D-01:** Follow established delta audit methodology from v15.0-v22.0 -- function-level changelog with per-function classification and proof
- **D-02:** Classification scheme: REFACTOR (identical behavior, formatting/structural only), INTENTIONAL (documented behavioral difference with correctness proof)
- **D-03:** Deleted functions verified as unreachable (no remaining callers in any contract)

### Scope
- **D-04:** Exactly 2 commits in scope: 93c05869 (DGNRS solo reward fold) and 520249a2 (specialized events, whale pass daily path, cleanup)
- **D-05:** Contracts in scope: JackpotModule, AdvanceModule, BurnieCoinflip, IDegenerusGameModules, IBurnieCoinflip
- **D-06:** Test file DgnrsSoloBucketReward.test.js added in 520249a2 is out of audit scope (test-only)

### Intentional Changes Requiring Correctness Proof
- **D-07:** Whale pass moved from early-burn/terminal to daily-only path -- prove early-burn and terminal now pay straight ETH, daily path correctly awards whale pass for solo bucket winners
- **D-08:** DGNRS solo reward folded into _processDailyEth -- prove same winner receives same total amount (was re-picking with different salt before, now inline with ETH winner)
- **D-09:** Specialized events (JackpotEthWin, JackpotTicketWin, JackpotBurnieWin, JackpotDgnrsWin, JackpotWhalePassWin) replace generic JackpotTicketWinner -- prove every old emission site now emits correct new event with correct fields

### Claude's Discretion
- Report structure and formatting
- Order of function analysis
- Level of detail in cosmetic/formatting change documentation

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Source Contracts (post-520249a2)
- `contracts/modules/DegenerusGameJackpotModule.sol` -- Primary audit target, contains all jackpot logic
- `contracts/modules/DegenerusGameAdvanceModule.sol` -- Caller of jackpot functions, awardFinalDayDgnrsReward removed
- `contracts/BurnieCoinflip.sol` -- creditFlipBatch signature change
- `contracts/interfaces/IDegenerusGameModules.sol` -- Interface changes (awardFinalDayDgnrsReward removed)
- `contracts/interfaces/IBurnieCoinflip.sol` -- creditFlipBatch interface change

### Git Diffs
- Commit 93c05869 -- DGNRS solo reward fold
- Commit 520249a2 -- Specialized events, whale pass daily path, cleanup

</canonical_refs>

<code_context>
## Existing Code Insights

### Key Changes Identified from Scout
- `_addClaimableEth` return signature changed: `uint256` -> `(uint256, uint24, uint32)` to surface rebuy fields for JackpotEthWin event
- `_validateTicketBudget` deleted -- lootbox budget now calculated inline (budget / 5)
- `_randTraitTicket` consolidated into `_randTraitTicketWithIndices` (now returns ticketIndexes)
- `_selectDailyCoinTargetLevel` simplified to pure function (removed winningTraitsPacked param)
- `awardFinalDayDgnrsReward` deleted from both JackpotModule and interface -- reward now inline in `_processDailyEth`
- `_processDailyEth` gains `isFinalPhysicalDay_` parameter for whale pass + DGNRS logic

### Established Patterns
- Prior delta audits use EQUIVALENT/INTENTIONAL/COSMETIC classification per function
- Each intentional change gets algebraic or trace-based correctness proof
- Deleted functions get caller-tree verification (no remaining references)

### Integration Points
- AdvanceModule calls into JackpotModule -- interface changes must match
- BurnieCoinflip called by JackpotModule -- signature changes must be consistent

</code_context>

<specifics>
## Specific Ideas

No specific requirements -- follow established delta audit methodology.

</specifics>

<deferred>
## Deferred Ideas

None -- analysis stayed within phase scope.

</deferred>

---

*Phase: 192-delta-extraction-behavioral-verification*
*Context gathered: 2026-04-06*
