---
phase: 51-redemption-lootbox-audit
plan: 04
subsystem: audit
tags: [access-control, accounting, delegatecall, unchecked-arithmetic, lootbox, cross-contract]

# Dependency graph
requires:
  - phase: 51-redemption-lootbox-audit
    provides: "RESEARCH.md with code locations, open questions, and pitfall analysis"
provides:
  - "REDM-06 verdict: SAFE (no ETH transfer) with MEDIUM sub-finding on unchecked subtraction underflow"
  - "REDM-07 verdict: SAFE (correct cross-contract access control at every hop)"
  - "New finding REDM-06-A for unchecked claimableWinnings underflow"
affects: [52-invariant-test-suite, 53-consolidated-findings]

# Tech tracking
tech-stack:
  added: []
  patterns: [cross-contract-call-chain-audit, delegatecall-context-verification, unchecked-arithmetic-analysis]

key-files:
  created:
    - ".planning/phases/51-redemption-lootbox-audit/51-04-access-control-reclassification-findings.md"
  modified: []

key-decisions:
  - "REDM-06-A classified as MEDIUM: unchecked underflow corrupts accounting but cannot be exploited for direct theft"

patterns-established:
  - "Cross-contract delegatecall audit: verify storage context, msg.sender preservation, no independent access control needed"
  - "Unchecked arithmetic audit: trace all credit/debit paths to verify balance sufficiency, check global vs per-address guards"

requirements-completed: [REDM-06, REDM-07]

# Metrics
duration: 10min
completed: 2026-03-21
---

# Phase 51 Plan 04: Access Control and Reclassification Findings Summary

**Cross-contract access control chain (sDGNRS->Game->LootboxModule) verified SAFE at every hop; lootbox reclassification confirmed as pure internal accounting with MEDIUM-severity unchecked subtraction underflow finding (REDM-06-A)**

## Performance

- **Duration:** 10 min
- **Started:** 2026-03-21T19:58:21Z
- **Completed:** 2026-03-21T20:08:44Z
- **Tasks:** 2
- **Files modified:** 2

## Accomplishments

- REDM-06 fully audited: lootbox reclassification confirmed as pure storage manipulation with no ETH transfer instructions in the entire code path (DegenerusGame.sol debit/credit, LootboxModule delegatecall, _resolveLootboxCommon)
- REDM-07 fully audited: three-hop call chain (sDGNRS external call -> Game msg.sender check -> LootboxModule delegatecall) verified correct with attack surface analysis covering EOA, malicious contract, reentrancy, and direct LootboxModule call scenarios
- New finding REDM-06-A discovered: unchecked subtraction on DegenerusGame.sol:1811 can underflow when `claimableWinnings[SDGNRS] < lootboxEth`, which occurs when prior claims drain sDGNRS's claimable via `_payEth` -> `game.claimWinnings()`. The checked `claimablePool -= amount` does not guard against per-address underflow because it's a global sum.
- uint128 cast for futurePrizePool credit proven safe (max 140 ETH = 1.4e20 << 3.4e38 = uint128.max)
- ContractAddresses verified as compile-time constants with CREATE nonce prediction (no runtime modification possible)

## Artifacts

| Artifact | Path | Content |
|----------|------|---------|
| Findings document | `.planning/phases/51-redemption-lootbox-audit/51-04-access-control-reclassification-findings.md` | REDM-06 and REDM-07 verdicts with line-referenced evidence |

## Verdicts

| Requirement | Verdict | Key Evidence |
|-------------|---------|-------------|
| REDM-06 | SAFE (no ETH transfer) | Zero `.call{value}`, `.transfer()`, `.send()` in Game.sol:1808-1844 or LootboxModule:849-1025 |
| REDM-06 sub-finding | FINDING (MEDIUM) | Unchecked `claimableWinnings[SDGNRS] -= amount` (line 1811) can underflow when prior claims drain sDGNRS's claimable |
| REDM-07 | SAFE | `msg.sender == SDGNRS` gate (line 1805) is first check; delegatecall preserves context; no independent LootboxModule access control needed |

## Task Commits

Each task was committed atomically:

1. **Task 1: Audit access control chain and lootbox reclassification** - `6a99b1f9` (feat)
2. **Task 2: Write plan summary** - [this commit] (docs)

## Files Created/Modified

- `.planning/phases/51-redemption-lootbox-audit/51-04-access-control-reclassification-findings.md` - Full audit findings with verdicts for REDM-06 and REDM-07, attack surface analysis, and new finding REDM-06-A
- `.planning/phases/51-redemption-lootbox-audit/51-04-SUMMARY.md` - This plan summary

## Decisions Made

- REDM-06-A severity classified as MEDIUM rather than HIGH: the unchecked underflow corrupts `claimableWinnings[SDGNRS]` accounting (inflated to near `uint256.max`) and creates DoS on future sDGNRS claims from Game, but cannot be exploited for direct theft because `claimablePool -= payout` in `_claimWinningsInternal` would revert on the inflated amount.

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None.

## User Setup Required

None - no external service configuration required.

## Key Observations for Downstream Phases

- **Phase 52 (INV-03):** The REDM-06-A finding should inform invariant test design. An invariant `claimableWinnings[SDGNRS] <= claimablePool` should be fuzzed with multi-actor claim sequences where prior claims drain sDGNRS's claimable via `_payEth` -> `game.claimWinnings()` before a second player's `claimRedemption`.
- **Phase 53 (consolidated findings):** REDM-06-A should be included in the final consolidated findings with a recommendation to either use checked arithmetic on line 1811 or restructure the accounting to debit from a dedicated redemption pool rather than from the general `claimableWinnings[SDGNRS]` balance.

## Next Phase Readiness

- All Phase 51 requirements (REDM-01 through REDM-07) now have verdicts pending other plan completions
- REDM-06-A finding ready for Phase 53 consolidation
- INV-03 invariant design informed by unchecked subtraction analysis

---
*Phase: 51-redemption-lootbox-audit*
*Completed: 2026-03-21*
