---
phase: 24-core-governance-security-audit
plan: 04
subsystem: security-audit
tags: [solidity, reentrancy, CEI, governance, VRF, _executeSwap, _voidAllActive]

# Dependency graph
requires:
  - phase: 24-01
    provides: Storage layout verification (GOV-01 confirmed no slot collisions)
provides:
  - GOV-07 verdict with systematic CEI trace and reentrancy path analysis
  - GOV-08 verdict with loop correctness and hard-set-to-zero analysis
  - Multi-proposal _voidAllActive test proving void-on-execute behavior
affects: [24-05, 24-06, 24-07, 24-08, 25-doc-sync]

# Tech tracking
tech-stack:
  added: []
  patterns: [CEI trace table with SSTORE and CALL mapping, adversarial reentrancy path enumeration]

key-files:
  created:
    - test/unit/VRFGovernance.test.js (2 new tests in _voidAllActive describe block)
  modified:
    - audit/v2.1-governance-verdicts.md (GOV-07 and GOV-08 verdicts appended)

key-decisions:
  - "GOV-07: KNOWN-ISSUE -- theoretical reentrancy via malicious coordinator exists but requires pre-existing governance control, not practically exploitable"
  - "GOV-08: PASS -- hard-set activeProposalCount = 0 is correct and more robust than decremental approach"
  - "Recommended mitigation for GOV-07: move _voidAllActive before external calls (Option A)"

patterns-established:
  - "CEI audit pattern: map every SSTORE and external CALL with line numbers, then enumerate reentry paths"
  - "Impersonate-game-for-sDGNRS pattern: use hardhat_impersonateAccount to give test accounts sDGNRS via transferFromPool"

requirements-completed: [GOV-07, GOV-08]

# Metrics
duration: 11min
completed: 2026-03-17
---

# Phase 24 Plan 04: _executeSwap CEI / Reentrancy and _voidAllActive Correctness Summary

**Systematic CEI trace of _executeSwap revealing theoretical sibling-proposal reentrancy (KNOWN-ISSUE, Low severity), plus _voidAllActive loop correctness proven with multi-proposal test evidence**

## Performance

- **Duration:** 11 min
- **Started:** 2026-03-17T19:15:46Z
- **Completed:** 2026-03-17T19:27:15Z
- **Tasks:** 2
- **Files modified:** 2

## Accomplishments
- GOV-07: Mapped all 6 SSTOREs and 5 external CALLs in _executeSwap with exact line numbers and trust classification
- GOV-07: Identified reentrancy path through malicious coordinator creating sibling proposal dual-execution, assessed as Low severity (requires pre-existing governance control)
- GOV-08: Proved _voidAllActive loop boundary correctness (1-indexed, <= condition), exceptId skip redundancy, hard-set-to-zero robustness, and reentrancy idempotency
- Added 2 tests proving _voidAllActive behavior with 3 simultaneous proposals and pre-killed proposal edge case

## Task Commits

Each task was committed atomically:

1. **Task 1: Audit _executeSwap CEI and reentrancy -- GOV-07** - `a47167b2` (feat)
2. **Task 2: Audit _voidAllActive and add multi-proposal test -- GOV-08** - `490d61a5` (feat)

## Files Created/Modified
- `audit/v2.1-governance-verdicts.md` - GOV-07 and GOV-08 verdicts with full CEI trace, reentrancy analysis, loop correctness, adversarial checks
- `test/unit/VRFGovernance.test.js` - 2 new tests in "_voidAllActive via execute with multiple proposals" describe block (34 total tests passing)

## Decisions Made
- GOV-07 rated KNOWN-ISSUE (not FAIL) because practical exploitation requires the attacker to already control governance via sDGNRS majority -- the reentrancy is not a privilege escalation
- Recommended Option A mitigation (move _voidAllActive before external calls) as lowest-friction defense-in-depth fix
- GOV-08 rated PASS -- the hard-set to 0 approach is provably correct and more resilient than decremental counting

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Corrupted build artifacts required clean rebuild**
- **Found during:** Task 2 (test execution)
- **Issue:** `npx hardhat test` failed with "Failed to parse build info: EOF while parsing a value" due to corrupted build-info JSON
- **Fix:** Ran `npx hardhat clean && npx hardhat compile` to regenerate artifacts
- **Files modified:** None (build artifacts only)
- **Verification:** All 34 tests pass after clean rebuild

---

**Total deviations:** 1 auto-fixed (1 blocking)
**Impact on plan:** Trivial build artifact issue, no scope creep.

## Issues Encountered
- sDGNRS has no public transfer function (soulbound token), so tests required impersonating the Game contract via `hardhat_impersonateAccount` to call `transferFromPool` and give the deployer voting weight. This pattern was borrowed from existing DGNRSLiquid.test.js.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- GOV-07 and GOV-08 complete; remaining GOV requirements (GOV-02, GOV-03, GOV-09, GOV-10) addressed by other plans
- Reentrancy finding in GOV-07 should be cross-referenced by WAR-01 (compromised admin scenario) in wave 4
- The impersonate-game-for-sDGNRS test pattern is available for reuse in any future voting tests

## Self-Check: PASSED

- audit/v2.1-governance-verdicts.md: FOUND
- test/unit/VRFGovernance.test.js: FOUND
- 24-04-SUMMARY.md: FOUND
- Commit a47167b2 (Task 1): FOUND
- Commit 490d61a5 (Task 2): FOUND

---
*Phase: 24-core-governance-security-audit*
*Completed: 2026-03-17*
