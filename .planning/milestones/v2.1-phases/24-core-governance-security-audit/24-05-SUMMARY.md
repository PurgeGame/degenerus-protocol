---
phase: 24-core-governance-security-audit
plan: 05
subsystem: audit
tags: [solidity, governance, voting, soulbound, overflow, expiry, circulating-supply]

# Dependency graph
requires:
  - phase: 24-01
    provides: "GOV-01 storage layout verification (slot map for all governance variables)"
provides:
  - "GOV-09 proposal expiry verdict (lazy expiry, revert rollback behavior)"
  - "GOV-10 circulatingSupply exclusion logic verdict"
  - "VOTE-01 sDGNRS frozen invariant (exhaustive 7-path mutation enumeration)"
  - "VOTE-02 circulatingSnapshot immutability proof"
  - "VOTE-03 uint8 activeProposalCount overflow analysis (KNOWN-ISSUE, LOW)"
affects: [24-06, 24-07, 24-08, 25-doc-sync]

# Tech tracking
tech-stack:
  added: []
  patterns: ["exhaustive balance-mutation enumeration for soulbound token audit"]

key-files:
  created: []
  modified:
    - "audit/v2.1-governance-verdicts.md"

key-decisions:
  - "GOV-09: Proposal expiry revert rolls back state changes -- activeProposalCount inflation is protective, not harmful"
  - "VOTE-01: sDGNRS has exactly 7 balance-mutation paths; all blocked during >20h stall except public burn (safe for vote arithmetic)"
  - "VOTE-03: uint8 overflow at 256 proposals rated LOW -- recommend require(activeProposalCount < 255) as minimal fix"

patterns-established:
  - "Balance-mutation enumeration: list every function that modifies balanceOf or totalSupply, classify each as BLOCKED/ALLOWED during governance-relevant periods"

requirements-completed: [GOV-09, GOV-10, VOTE-01, VOTE-02, VOTE-03]

# Metrics
duration: 15min
completed: 2026-03-17
---

# Phase 24 Plan 05: Vote Integrity and Expiry Audit Summary

**Exhaustive sDGNRS mutation path enumeration proving vote integrity during VRF stall, plus proposal expiry/circulatingSupply/uint8 overflow verdicts**

## Performance

- **Duration:** 15 min
- **Started:** 2026-03-17T19:15:50Z
- **Completed:** 2026-03-17T19:30:29Z
- **Tasks:** 2
- **Files modified:** 1

## Accomplishments
- GOV-09 PASS: Lazy expiry analyzed -- revert rolls back p.state and activeProposalCount changes, counter stays inflated (protective behavior, pauses death clock longer)
- GOV-10 PASS: circulatingSupply correctly excludes undistributed pools (SDGNRS) and DGNRS wrapper backing; underflow impossible under checked Solidity 0.8.34 arithmetic
- VOTE-01 PASS: All 7 sDGNRS balance-mutation paths exhaustively enumerated (mint, pool distribution, pool rebalance, wrapperTransferTo, burn, burnRemainingPools, peer transfer); all blocked during >20h stall except burn which only reduces caller's own balance
- VOTE-02 PASS: circulatingSnapshot written exactly once (propose() line 424), verified via grep -- no other write path exists
- VOTE-03 KNOWN-ISSUE (LOW): uint8 wraps 255->0 after 256 proposals, causing anyProposalActive() to return false; exploitable for ~$3000 gas cost

## Task Commits

Each task was committed atomically:

1. **Task 1: Audit expiry and circulatingSupply -- GOV-09, GOV-10** - `cc460bec` (feat)
2. **Task 2: Audit vote integrity invariants -- VOTE-01, VOTE-02, VOTE-03** - `7016e0b8` (feat)

## Files Created/Modified
- `audit/v2.1-governance-verdicts.md` - Added GOV-09, GOV-10, VOTE-01, VOTE-02, VOTE-03 verdicts with full adversarial analysis

## Decisions Made
- GOV-09: The revert-rollback behavior of expiry (state changes rolled back) means activeProposalCount inflation is permanent until _voidAllActive resets it. Classified as INFORMATIONAL because the inflation is protective (keeps death clock paused).
- VOTE-01: The 20h boundary edge case where unwrapTo is briefly allowed (WAR-04) does not meaningfully undermine vote integrity -- single-block window, bounded by DGNRS wrapper balance.
- VOTE-03: Rated LOW severity despite feasibility ($3000 cost) because the primary harm (death clock unpause) is bounded by the clock's own 120-day timeout and requires sustained VRF failure. Recommended Option A mitigation (require check).

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
None

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- All 5 requirement verdicts (GOV-09, GOV-10, VOTE-01, VOTE-02, VOTE-03) complete
- VOTE-01 confirms the frozen-supply invariant that GOV-03 depends on
- VOTE-03 KNOWN-ISSUE should be tracked for Phase 25 documentation
- Ready for remaining Phase 24 plans (cross-contract, warden simulation)

## Self-Check: PASSED

- [x] `audit/v2.1-governance-verdicts.md` exists
- [x] `24-05-SUMMARY.md` exists
- [x] Commit `cc460bec` (Task 1: GOV-09, GOV-10) found in git log
- [x] Commit `7016e0b8` (Task 2: VOTE-01, VOTE-02, VOTE-03) found in git log
- [x] All 5 verdict sections (GOV-09, GOV-10, VOTE-01, VOTE-02, VOTE-03) present in verdicts file
- [x] VRFGovernance.test.js: 38 passing, 0 failing

---
*Phase: 24-core-governance-security-audit*
*Completed: 2026-03-17*
