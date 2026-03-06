---
phase: 04-eth-token-accounting-integrity
plan: 08
subsystem: testing
tags: [vault, dgve, dgvb, share-redemption, steth, burnie, accounting]

# Dependency graph
requires:
  - phase: 04-eth-token-accounting-integrity
    provides: "RESEARCH.md with vault yield architecture and share formula references"
provides:
  - "ACCT-09 PASS verdict: vault share redemption formulas verified correct"
  - "DGVE/DGVB rounding direction confirmed vault-favorable"
  - "Refill mechanism safety analysis (no residual, no race, no overflow)"
  - "stETH passive yield accrual mechanism confirmed"
  - "Cross-contract ETH/stETH/BURNIE flow verification"
affects: [04-09-burnie-supply-invariant]

# Tech tracking
tech-stack:
  added: []
  patterns: [share-based-proportional-redemption, vault-favorable-rounding, atomic-refill]

key-files:
  created: []
  modified:
    - ".planning/phases/04-eth-token-accounting-integrity/04-08-FINDINGS-vault-accounting.md"

key-decisions:
  - "ACCT-09 PASS: vault share redemption formulas are mathematically correct with vault-favorable rounding"

patterns-established:
  - "Share redemption: claimValue = (reserve * sharesBurned) / totalSupply -- standard proportional, floors against claimer"
  - "Refill guard: supplyBefore == amount (exact total supply match) prevents partial-burn trigger"

requirements-completed: [ACCT-09]

# Metrics
duration: 2min
completed: 2026-03-06
---

# Phase 04 Plan 08: Vault Accounting Summary

**DGVE/DGVB share redemption formulas verified correct with vault-favorable rounding; refill mechanism safe; stETH yield passively accrues to DGVE holders**

## Performance

- **Duration:** 2 min
- **Started:** 2026-03-06T19:37:20Z
- **Completed:** 2026-03-06T19:39:13Z
- **Tasks:** 1
- **Files modified:** 1

## Accomplishments
- Verified DGVE redemption formula: `claimValue = (reserve * amount) / supply` where reserve = ETH + stETH + game claimable winnings
- Verified DGVB redemption formula: `coinOut = (coinBal * amount) / supply` where coinBal = vaultAllowance + balance + coinflip claimable
- Confirmed integer division floors against claimer (vault-favorable rounding) for both formulas
- Confirmed refill mechanism is atomic, race-free, and safe from overflow
- Confirmed stETH yield passively increases DGVE per-share value via fresh `steth.balanceOf()` reads
- Traced cross-contract flows: ETH via receive()/call{value}, stETH via transfer(), BURNIE via vaultEscrow/vaultMintTo
- Fixed minor line reference inaccuracies in findings document (vaultMintTo line 694, vaultEscrow line 677, _sendToVault line 182)
- Fixed vault owner threshold reference from >30% to correct >50.1%
- ACCT-09: PASS

## Task Commits

Each task was committed atomically:

1. **Task 1: Audit DGVE and DGVB share redemption formulas and vault refill mechanism** - `c473a14` (feat)

## Files Created/Modified
- `.planning/phases/04-eth-token-accounting-integrity/04-08-FINDINGS-vault-accounting.md` - Comprehensive vault accounting audit with ACCT-09 verdict

## Decisions Made
- ACCT-09 PASS: The DegenerusVault share-based redemption system is mathematically correct for both DGVE (ETH+stETH) and DGVB (BURNIE). Rounding favors the vault, refill mechanism is safe, and stETH yield accrues passively.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Fixed incorrect line references and threshold in existing findings**
- **Found during:** Task 1 (audit verification)
- **Issue:** Existing findings had stale line references (vaultMintTo 674->694, vaultEscrow 657->677, _sendToVault 249->182) and incorrect vault owner threshold (>30% -> >50.1%)
- **Fix:** Updated line numbers and threshold to match current source
- **Files modified:** 04-08-FINDINGS-vault-accounting.md
- **Verification:** Cross-referenced against live source code
- **Committed in:** c473a14

---

**Total deviations:** 1 auto-fixed (1 bug)
**Impact on plan:** Minor reference corrections. No scope creep.

## Issues Encountered
None

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Vault accounting audit complete, ACCT-09 satisfied
- Ready for 04-09 (BurnieCoin supply invariant audit)

## Self-Check: PASSED

- [x] 04-08-FINDINGS-vault-accounting.md exists
- [x] 04-08-SUMMARY.md exists
- [x] Commit c473a14 exists in git history

---
*Phase: 04-eth-token-accounting-integrity*
*Completed: 2026-03-06*
