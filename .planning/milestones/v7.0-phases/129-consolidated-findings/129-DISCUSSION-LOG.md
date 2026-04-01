# Phase 129: Consolidated Findings - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-03-26
**Phase:** 129-consolidated-findings
**Areas discussed:** Finding dispositions (user-driven review of all findings by severity)

---

## Finding-by-Finding Review

User requested to see all findings by severity and discuss each before deciding KNOWN-ISSUES updates.

### GOV-01: Permissionless resolveLevel desync (INVESTIGATE)

**User's response:** "didn't we already fix gov 01"
**Verification:** Confirmed — commit 1f65cc1c renamed `resolveLevel` → `pickCharity` with `onlyGame` modifier. Fix was applied before audit began.
**Disposition:** FIXED

### GOV-02: Vault owner 6th proposal (INFO)

**User's response:** "02, 03 don't matter"
**Disposition:** INFO, not actionable

### GOV-03: No minimum governance voting period (INFO)

**User's response:** "02, 03 don't matter"
**Disposition:** INFO, not actionable

### GOV-04: Vault owner 5% vote bonus accumulates (INFO)

**User's response:** "what does 04 even mean? I get 5% bonus vote on each proposal, that is intended. if it can stack somehow then we need to address that but I think we covered it"
**Clarification:** 5% is a flat per-vote bonus (line 420: `weight += snapshot * 500 / 10000`), not compounding across proposals. Each proposal tally is independent.
**Disposition:** INFO, intended behavior, non-stacking

### GH-01: Path A handleGameOver removal — GNRUS dilution (INFO)

**User's response:** "why would this dilute redemption? path a still can't pay out anything from claimable can it (and realistically it's basically impossible to get there)"
**Clarification:** Path A fires only when claimable winnings consume entire balance — practically unreachable. Charity ETH from yield surplus would be trivially small.
**User follow-up:** "I mean you can put the burns in path a if you want but other than that none of this stuff is anything"
**Disposition:** INFO, could add burn to Path A as nice-to-have, deferred

### GH-02: resolveLevel griefing from game hooks (INFO)

**Same root cause as GOV-01.**
**Disposition:** FIXED (same commit 1f65cc1c)

### AFF-01: referPlayer to precompile address (INFO)

**User's response:** "isn't address(1) auto the vault?"
**Clarification:** No — `address(1)` is the ecrecover precompile. The vault is at `ContractAddresses.VAULT` (a different address). Default codes use `bytes32(uint256(uint160(addr)))` so `address(1)` → `bytes32(1)`. Self-inflicted, no protocol impact.
**Disposition:** INFO, not actionable

### Contract Naming

**User's correction:** "it's GNRUS"
**Context:** Contract was renamed from DegenerusCharity to GNRUS in commit 1f65cc1c. Report must use current name.

---

## Claude's Discretion

- Report formatting and section ordering
- Plan-drift annotation verbosity
- Summary statistics table inclusion

## Deferred Ideas

- Path A burn call (optional cleanup, user's discretion for future milestone)
