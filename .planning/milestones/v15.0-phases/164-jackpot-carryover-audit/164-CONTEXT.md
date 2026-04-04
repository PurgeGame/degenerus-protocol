# Phase 164: Jackpot Carryover Audit - Context

**Gathered:** 2026-04-02
**Status:** Ready for planning

<domain>
## Phase Boundary

Prove the jackpot carryover ticket distribution and final-day behavior are correct. This covers the v13.0 carryover redesign (Phase 158.1: single-pass ticket distribution replacing multi-call ETH state machine) and the subsequent `fix(jackpot)` commit that fixed carryover ticket level routing, source range, and final-day behavior.

</domain>

<decisions>
## Implementation Decisions

### D-01: Audit scope
Two subsystems to verify:
1. **Carryover ticket distribution** — single-pass distribution in EndgameModule/JackpotModule, source range 1-4, budget 0.5% of futurePrizePool, tickets purchased at current level
2. **Final-day jackpot behavior** — when `lastPurchaseDay` is detected, tickets route to `level + 1` to prevent stranding

### D-02: Verification method
Trace the code paths end-to-end. For each claim:
- Identify the code location (contract, function, line)
- Verify the logic matches the specification
- Check edge cases (zero budget, zero tickets, boundary levels)
- Produce SAFE/VULNERABLE verdict per function

### D-03: Output format
Audit report at `.planning/phases/164-jackpot-carryover-audit/164-CARRYOVER-AUDIT.md` with verdicts per function, edge case analysis, and any findings.

### D-04: Key changes to audit
From the changelog (162-CHANGELOG.md):
- Carryover ETH state machine removal (v13.0 Phase 158.1)
- `fix(jackpot)` commit: carryover tickets at current level, source range 1-4, final day to lvl+1
- Storage gaps from removed carryover variables

</decisions>

<canonical_refs>
## Canonical References

### Contracts to audit
- `contracts/modules/DegenerusGameJackpotModule.sol` — carryover distribution, final-day detection
- `contracts/modules/DegenerusGameEndgameModule.sol` — endgame carryover path
- `contracts/modules/DegenerusGameAdvanceModule.sol` — level advancement, lastPurchaseDay detection

### Prior work
- `.planning/phases/162-changelog-extraction/162-CHANGELOG.md` — identifies all carryover-related changes
- `.planning/phases/163-level-system-documentation/163-LEVEL-SYSTEM.md` — level/ticket routing reference

</canonical_refs>

<code_context>
## Existing Code Insights

### What changed (from changelog)
- Phase 158.1 removed the multi-call carryover ETH state machine (dailyEthPhase, carryoverEthPending, etc.)
- Replaced with single-pass ticket distribution using 0.5% of futurePrizePool budget
- `fix(jackpot)` corrected level routing (current level, not level+1) and source range (1-4)
- Final-day override routes to level+1 when lastPurchaseDay detected

</code_context>

<specifics>
## Specific Ideas

User specifically called out "the jackpot changes we need to make sure didn't fuck anything up" — this is the primary concern.

</specifics>

<deferred>
## Deferred Ideas

None

</deferred>

---

*Phase: 164-jackpot-carryover-audit*
*Context gathered: 2026-04-02*
