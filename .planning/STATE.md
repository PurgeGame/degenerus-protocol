---
gsd_state_version: 1.0
milestone: v3.8
milestone_name: VRF Commitment Window Audit
status: Ready to execute
stopped_at: Completed 72-01-PLAN.md
last_updated: "2026-03-23T00:23:54.502Z"
progress:
  total_phases: 6
  completed_phases: 4
  total_plans: 13
  completed_plans: 11
---

# State

## Project Reference

See: .planning/PROJECT.md (updated 2026-03-22)

**Core value:** Every finding a C4A warden could submit is identified and either fixed or documented as known before the audit begins.
**Current focus:** Phase 72 — ticket-queue-deep-dive-pattern-scan

## Current Position

Phase: 72 (ticket-queue-deep-dive-pattern-scan) — EXECUTING
Plan: 2 of 2

## Accumulated Context

### Decisions

None (fresh milestone).

- [Phase 68-commitment-window-inventory]: Degenerette confirmed as 7th VRF-dependent outcome category (reads lootboxRngWordByIndex at resolution)
- [Phase 68-commitment-window-inventory]: Backward trace independently found 17 variables not in forward trace -- validates forward+backward methodology
- [Phase 68-commitment-window-inventory]: Mutation surface: search ALL modules for each variable write due to delegatecall shared storage
- [Phase 68-commitment-window-inventory]: All 51 variable slot numbers validated via forge inspect -- zero discrepancies
- [Phase 69]: All 51 VRF-touched variables SAFE: five layered defense mechanisms (rngLockedFlag, prizePoolFrozen, double-buffer, index-keying, day-keying) provide complete commitment window coverage
- [Phase 69]: Mid-day VRF window harmless by architecture: rawFulfillRandomWords only stores lootboxRngWordByIndex without reading mutable state
- [Phase 73]: Used // @deprecated comments instead of NatSpec /// @deprecated (Solidity 0.8.34 rejects @deprecated on non-public state variables)
- [Phase 73]: BoonPacked struct at storage slot 107 (after lastTerminalDecClaimRound at slot 106) -- all 29 old boon mapping slots preserved unchanged
- [Phase 69-mutation-verdicts]: CW-04 exhaustive proof: all 87 permissionless paths enumerated with 7 protection categories, count verified
- [Phase 73]: Lootbox boost event emission decodes tier back to BPS via _lootboxTierToBps to preserve original event values
- [Phase 73]: Lazy pass boon consumption re-reads slot1 before clearing to handle deity-path pre-clearing correctly
- [Phase 70]: Game-over deposits unblocked by design -- lost deposits are INFO-level, not exploitable
- [Phase 70]: sDGNRS auto-claim during processCoinflipPayouts safe -- BAF exclusion (line 556) prevents rngLocked revert
- [Phase 70]: All 10 BurnieCoinflip entry points SAFE via five layered protections: day+1 keying, rngLockedFlag, pure-function outcome, access control, outcome-irrelevant writes
- [Phase 71]: Daily VRF word has 10 consumers (not 9): awardFinalDayDgnrsReward is a distinct consumer at JackpotModule:773
- [Phase 71]: DAYRNG-02 SAFE: dual sub-window proof (Periods A/B/C), 11 permissionless actions tabulated, depositCoinflip targets day+1, _requestRng before _swapAndFreeze
- [Phase 70]: All 7 multi-TX attack sequences SAFE: day+1 keying is the primary defense defeating 4/7 attacks
- [Phase 70]: Game-over predictable fallback is Informational: deposits allowed but stranded due to day+1 keying
- [Phase 70]: rngLockedFlag is the only defense for auto-rebuy extraction (Attack 2) -- without it, carry extraction after seeing VRF word would be exploitable
- [Phase 71]: Contamination defined precisely as day N RNG OUTCOME influencing day N+1 RNG WORD or SELECTION MECHANISM -- carry-over game context excluded by definition
- [Phase 71]: Exhaustive grep confirms rngWordByDay has exactly 2 write locations (lines 1533, 1484) -- all others are reads/guards, proving write-once immutability
- [Phase 72]: Severity MEDIUM not HIGH: stolen asset is BURNIE (flipCredit) not ETH
- [Phase 72]: Fix Option A (_tqWriteKey -> _tqReadKey) recommended: root cause fix, one-line, aligns with processTicketBatch pattern
- [Phase 72]: Both call paths affected: payDailyJackpotCoinAndTickets (jackpot phase) AND payDailyCoinJackpot (purchase phase)
- [Phase 72]: purchaseCoin() equally exploitable: COIN_PURCHASE_CUTOFF is liveness guard (90d), not commitment window guard

### Pending Todos

None.

### Blockers/Concerns

- Ticket queue swap during jackpot phase is a known commitment window violation — motivates this milestone.
- COIN-01 and DAYRNG-01 were previously deferred in ROADMAP.md — now promoted to v3.8 scope.

## Session Continuity

Last session: 2026-03-23T00:23:54.500Z
Stopped at: Completed 72-01-PLAN.md
Resume file: None
