---
phase: 176-core-game-token-contract-comment-sweep
plan: "02"
subsystem: audit
tags: [comment-sweep, burnie, coinflip, access-control, natspec]

requires:
  - phase: 176-01
    provides: comment sweep methodology and findings format for phase 176

provides:
  - "176-02-FINDINGS.md: 5 LOW + 7 INFO findings across BurnieCoin and BurnieCoinflip"
  - "BurnieCoin access control NatSpec discrepancies catalogued"
  - "BurnieCoinflip creditor expansion and mintForGame merger verified"

affects:
  - 176-core-game-token-contract-comment-sweep
  - v15.0 comment accuracy requirements (CMT-03)

tech-stack:
  added: []
  patterns:
    - "Line-by-line comment vs code comparison for audit documentation"

key-files:
  created:
    - ".planning/phases/176-core-game-token-contract-comment-sweep/176-02-FINDINGS.md"
  modified: []

key-decisions:
  - "BCF-05 downgraded from LOW to INFO after re-checking: presale 156% max is accurate for the 1/20 lucky roll"
  - "BCF-06 removed entirely: payout formula comment is accurate"
  - "BCF-04 kept as LOW: claimCoinflipsForRedemption 'skips RNG lock' is only true for sDGNRS caller, misleads for general redemption use"

patterns-established:
  - "All error-name mismatches flagged as LOW when the wrong error name would mislead integrators about who the gating party is"

requirements-completed:
  - CMT-03

duration: 5min
completed: 2026-04-03
---

# Phase 176 Plan 02: BurnieCoin + BurnieCoinflip Comment Sweep Summary

**BurnieCoin and BurnieCoinflip comment sweep — 5 LOW (access control misstatements + error name mismatches) and 7 INFO (orphaned sections, missing callers, minor inaccuracies); creditor expansion and mintForGame merger verified clean**

## Performance

- **Duration:** 5 min
- **Started:** 2026-04-03T21:50:20Z
- **Completed:** 2026-04-03T21:55:27Z
- **Tasks:** 2
- **Files modified:** 1

## Accomplishments

- BurnieCoin (717 lines) swept end-to-end; 7 findings logged (3 LOW, 4 INFO)
- BurnieCoinflip (1159 lines) swept end-to-end; 5 findings logged (2 LOW, 3 INFO)
- v10.1 creditor expansion verified: no stale single-creditor comments, BCF-01 catches incorrect inclusion of BURNIE in NatSpec
- mintForGame merger verified: no stale mintForCoinflip references in BurnieCoinflip code or comments
- Mint/burn access control table compiled confirming which contracts can call which functions

## Task Commits

1. **Task 1: Sweep BurnieCoin.sol + Task 2: Sweep BurnieCoinflip.sol** - `5534326e` (feat: combined into single findings file)

**Plan metadata:** (docs commit follows)

## Files Created/Modified

- `.planning/phases/176-core-game-token-contract-comment-sweep/176-02-FINDINGS.md` — Complete findings for BurnieCoin and BurnieCoinflip with 12 findings (5 LOW, 7 INFO)

## Decisions Made

- BCF-05 (presale max comment) downgraded from LOW to INFO: the comment "max is 156% during presale" is technically accurate for the 1/20 lucky roll — it states the absolute maximum. It is not a misleading access-control or math error.
- BCF-04 kept as LOW: `claimCoinflipsForRedemption` NatSpec says "skips RNG lock" but this is only unconditionally true for sDGNRS callers. For other players with BAF credits, the RNG lock can still revert. The comment overstates the guarantee.

## Deviations from Plan

None — plan executed exactly as written. Both contracts read in full and all comment-code discrepancies logged.

## Issues Encountered

None. Both contracts were read completely. The findings file was force-added via `git add -f` because `.planning/` is gitignored in the project.

## Known Stubs

None — this plan produces only a findings document, not contract code.

## Next Phase Readiness

- 176-02-FINDINGS.md is complete and self-contained; a reader can understand each finding without opening the contracts
- 176-03 (DegenerusStonk, GNRUS, StakedDegenerusStonk) is a separate plan in this phase and may run in parallel

---
*Phase: 176-core-game-token-contract-comment-sweep*
*Completed: 2026-04-03*
