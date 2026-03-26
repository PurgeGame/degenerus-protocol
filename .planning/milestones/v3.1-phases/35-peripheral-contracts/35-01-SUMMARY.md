---
phase: 35-peripheral-contracts
plan: 01
subsystem: audit
tags: [solidity, natspec, comment-audit, coinflip, burnie, intent-drift]

# Dependency graph
requires:
  - phase: 34-token-contracts
    provides: "CMT/DRIFT numbering endpoint (CMT-058, DRIFT-003) and coinflip split orphaned NatSpec pattern"
provides:
  - "BurnieCoinflip.sol comment audit findings (CMT-072 through CMT-076)"
  - "Phase 35 findings file with BurnieCoinflip section"
  - "Confirmed no post-Phase-29 changes to BurnieCoinflip.sol"
affects: [35-peripheral-contracts]

# Tech tracking
tech-stack:
  added: []
  patterns: ["Error reuse pattern (OnlyBurnieCoin in _resolvePlayer) classified as CMT following CMT-043 precedent"]

key-files:
  created: []
  modified:
    - "audit/v3.1-findings-35-peripheral-contracts.md"

key-decisions:
  - "CMT numbering starts at CMT-072 (not CMT-059 as originally planned) because concurrent plan executions (35-02, 35-03) claimed CMT-059 through CMT-071"
  - "Error reuse at line 1142 classified as CMT-076 (not DRIFT) following Phase 34 CMT-043 precedent for semantically wrong error reuse"
  - "0 DRIFT findings: full intent drift scan found no vestigial BurnieCoin state references, no unnecessary guards post-split"

patterns-established:
  - "Coinflip split artifact detection: JACKPOT_RESET_TIME unused constant follows orphaned NatSpec pattern from Phase 34"
  - "Error reuse across helpers: _resolvePlayer uses OnlyBurnieCoin while _requireApproved uses NotApproved for same check"

requirements-completed: [CMT-05, DRIFT-05]

# Metrics
duration: 10min
completed: 2026-03-19
---

# Phase 35 Plan 01: BurnieCoinflip.sol Comment Audit Summary

**BurnieCoinflip.sol (1,154 lines, 62 NatSpec tags, 37 functions) fully reviewed -- 5 CMT findings, 0 DRIFT: vestigial split constant, sparse NatSpec on operator deposit, and error reuse inconsistency**

## Performance

- **Duration:** 10 min
- **Started:** 2026-03-19T05:59:04Z
- **Completed:** 2026-03-19T06:09:41Z
- **Tasks:** 2
- **Files modified:** 1

## Accomplishments
- BurnieCoinflip.sol fully audited: 62 NatSpec tags verified, ~152 comment lines reviewed, 37 functions cross-referenced
- Phase 35 findings file BurnieCoinflip section created with 5 CMT findings (CMT-072 through CMT-076)
- Full intent drift scan completed: no vestigial BurnieCoin state references, no unnecessary post-split guards
- Pre-identified error reuse pattern (OnlyBurnieCoin at line 1142) formally evaluated and flagged with _requireApproved inconsistency
- Summary table updated with actual BurnieCoinflip counts (5 CMT, 0 DRIFT, 5 total)

## Task Commits

Each task was committed atomically:

1. **Task 1: BurnieCoinflip.sol first half audit** - `4bbde1ef` (feat -- BurnieCoinflip section creation with CMT-072 through CMT-075 included in concurrent commit)
2. **Task 2: BurnieCoinflip.sol second half audit** - `af3eaf8b` (feat -- CMT-076, summary table update, review completion marker)

## Files Created/Modified
- `audit/v3.1-findings-35-peripheral-contracts.md` - Added BurnieCoinflip.sol section with 5 findings (CMT-072 through CMT-076), summary table row updated

## Decisions Made
- **CMT numbering offset:** Plan specified CMT-059 start, but concurrent Plans 35-02 and 35-03 claimed CMT-059 through CMT-071. BurnieCoinflip starts at CMT-072. Sequential correctness maintained.
- **Error reuse classification:** OnlyBurnieCoin at line 1142 classified as CMT (comment-inaccuracy) rather than DRIFT (intent-drift), following Phase 34 CMT-043 precedent for error reuse patterns.
- **No DRIFT findings:** Full contract scan found no vestigial references from the BurnieCoin/BurnieCoinflip split affecting intent. JACKPOT_RESET_TIME is dead code (CMT) not a behavioral drift.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] CMT numbering offset due to concurrent plan execution**
- **Found during:** Task 1 (findings file creation)
- **Issue:** Plan specified CMT-059 as start number, but the findings file already contained CMT-059 through CMT-071 from concurrent Plans 35-02 and 35-03
- **Fix:** Continued numbering sequentially from CMT-072 to avoid collisions
- **Files modified:** audit/v3.1-findings-35-peripheral-contracts.md
- **Verification:** `grep '### CMT-07' audit/v3.1-findings-35-peripheral-contracts.md` shows CMT-072 through CMT-076 without gaps
- **Committed in:** 4bbde1ef (Task 1), af3eaf8b (Task 2)

---

**Total deviations:** 1 auto-fixed (1 blocking)
**Impact on plan:** Numbering offset necessary to maintain sequential correctness. No scope creep.

## Issues Encountered
- Task 1 findings were committed as part of a concurrent plan's commit (4bbde1ef for 35-03) due to shared file modifications. Task 2 has a dedicated commit (af3eaf8b).

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- BurnieCoinflip.sol audit complete; remaining Phase 35 contracts ready for review in Plans 02-04
- CMT numbering continues from CMT-072+ (BurnieCoinflip) -- next contract sections must check current max CMT number
- DRIFT numbering continues from DRIFT-005 (next after DegenerusQuests DRIFT-004)
- No blockers for remaining plans

## Self-Check: PASSED

- FOUND: audit/v3.1-findings-35-peripheral-contracts.md
- FOUND: .planning/phases/35-peripheral-contracts/35-01-SUMMARY.md
- FOUND: commit af3eaf8b (Task 2)
- FOUND: commit 4bbde1ef (Task 1 -- concurrent commit)

---
*Phase: 35-peripheral-contracts*
*Completed: 2026-03-19*
