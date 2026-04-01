---
phase: 51-redemption-lootbox-audit
plan: 01
subsystem: audit
tags: [solidity, sdgnrs, redemption, lootbox, split, gameover, arithmetic-proof]

requires:
  - phase: 44-delta-audit-redemption-correctness
    provides: "CP-08, CP-06, Seam-1, CP-07 fixes verified"
provides:
  - "REDM-01 verdict: 50/50 split routing SAFE"
  - "REDM-02 verdict: gameOver bypass SAFE"
  - "pendingRedemptionEthValue underflow analysis (no underflow)"
  - "Floor-division inequality proof for aggregate claim safety"
affects: [51-02, 51-03, 51-04, phase-52]

tech-stack:
  added: []
  patterns: [floor-division-inequality-proof, conservation-identity-verification]

key-files:
  created:
    - .planning/phases/51-redemption-lootbox-audit/51-01-split-routing-findings.md
  modified: []

key-decisions:
  - "REDM-01 SAFE: 50/50 split conservation proven algebraically (ethDirect + lootboxEth == totalRolledEth)"
  - "REDM-02 SAFE: gameOver bypass confirmed pure ETH/stETH with no lootbox or BURNIE"
  - "INFO finding: rounding dust accumulates in pendingRedemptionEthValue (negligible, no action needed)"
  - "gameOver transition during active claims is safe by design (player benefits from 100% direct ETH)"

patterns-established:
  - "Floor-division inequality: sum_i(floor(a_i*r/d)) <= floor(sum(a_i)*r/d) used to prove aggregate safety"

requirements-completed: [REDM-01, REDM-02]

duration: 5min
completed: 2026-03-21
---

# Phase 51 Plan 01: Split Routing and GameOver Bypass Summary

**50/50 sDGNRS redemption split proven correct with algebraic conservation proof; gameOver bypass confirmed pure ETH/stETH routing with no lootbox or BURNIE; pendingRedemptionEthValue underflow impossible via floor-division inequality**

## Performance

- **Duration:** 5 min
- **Started:** 2026-03-21T19:58:27Z
- **Completed:** 2026-03-21T20:03:27Z
- **Tasks:** 2
- **Files modified:** 2

## Accomplishments

- REDM-01 SAFE: Proved `ethDirect + lootboxEth == totalRolledEth` for all inputs via algebraic identity `floor(x/2) + (x - floor(x/2)) = x`
- REDM-02 SAFE: Confirmed gameOver bypass routes 100% to direct ETH, `_deterministicBurnFrom` emits `Burn(..., 0)` with no BURNIE
- Proved `pendingRedemptionEthValue` cannot underflow at line 609 using floor-division inequality across aggregate claims
- Analyzed gameOver transition during active claims (Pitfall 6): safe by design, favorable to player
- Identified INFO-severity rounding dust accumulation (harmless, no action needed)

## Task Commits

Each task was committed atomically:

1. **Task 1: Audit 50/50 split routing and gameOver bypass** - `6c00a152` (feat)
2. **Task 2: Write plan summary** - (this commit)

## Artifacts

- `.planning/phases/51-redemption-lootbox-audit/51-01-split-routing-findings.md` -- Full audit findings with line-referenced verdicts and arithmetic proofs for REDM-01 and REDM-02

## Files Created/Modified

- `.planning/phases/51-redemption-lootbox-audit/51-01-split-routing-findings.md` - Audit findings with verdicts for REDM-01 (50/50 split) and REDM-02 (gameOver bypass)
- `.planning/phases/51-redemption-lootbox-audit/51-01-SUMMARY.md` - This summary

## Verdicts

| Requirement | Verdict | Key Evidence |
|-------------|---------|--------------|
| REDM-01 | **SAFE** | `ethDirect + lootboxEth == totalRolledEth` proven algebraically; pendingRedemptionEthValue underflow impossible; activity score reversal correct |
| REDM-02 | **SAFE** | `isGameOver` routes 100% direct ETH; `_deterministicBurnFrom` emits Burn with burnieOut=0; no call to resolveRedemptionLootbox; CP-08 fix verified at line 487 |

## New Findings

| ID | Severity | Description |
|----|----------|-------------|
| INFO-01 | INFO | Rounding dust accumulates in `pendingRedemptionEthValue` (at most n-1 wei per period for n claimants). No exploit vector, no economic impact. |

## Decisions Made

- Both REDM-01 and REDM-02 are SAFE -- no code changes needed
- gameOver transition during active claims is intentional design (100% direct ETH benefits the player)
- Rounding dust accumulation is harmless and requires no mitigation

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- REDM-01 and REDM-02 are closed. Ready for Plan 02 (daily cap enforcement and slot packing: REDM-03, REDM-05).
- The pendingRedemptionEthValue underflow analysis from this plan is prerequisite context for REDM-03's daily cap review (both share the same segregation accounting).
- No blockers for downstream plans.

## Self-Check: PASSED

- [x] 51-01-split-routing-findings.md exists
- [x] 51-01-SUMMARY.md exists
- [x] Commit 6c00a152 exists (Task 1)
- [x] Commit c4726ce0 exists (Task 2)

---
*Phase: 51-redemption-lootbox-audit*
*Completed: 2026-03-21*
