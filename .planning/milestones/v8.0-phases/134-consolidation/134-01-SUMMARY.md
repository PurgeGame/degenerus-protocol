---
phase: 134-consolidation
plan: 01
subsystem: audit
tags: [slither, 4naly3er, known-issues, bot-race, erc-20, events, dead-code]

# Dependency graph
requires:
  - phase: 130-bot-race
    provides: "Slither + 4naly3er triage (5 DOCUMENT + 22 DOCUMENT)"
  - phase: 131-erc-20-compliance
    provides: "5 ERC-20 deviation entries ready to paste"
  - phase: 132-event-correctness
    provides: "30 INFO event findings summary"
  - phase: 133-comment-re-scan
    provides: "116 NC instance dispositions (72 FIXED, 12 JUSTIFIED, 32 FP)"
provides:
  - "KNOWN-ISSUES.md expanded with all DOCUMENT findings for C4A warden pre-disclosure"
  - "GAS-10 immutable candidate review (all 10 FP)"
  - "Dead code _lootboxBpsToTier removal (pending user approval)"
affects: [134-02, audit-submission]

# Tech tracking
tech-stack:
  added: []
  patterns: ["KNOWN-ISSUES.md organized by concern category with detector IDs per D-03"]

key-files:
  created:
    - "audit/gas10-immutable-candidates.md"
  modified:
    - "KNOWN-ISSUES.md"
    - "contracts/storage/DegenerusGameStorage.sol (pending approval)"

key-decisions:
  - "GAS-10 all 10 instances are false positives -- 6 already immutable, 1 string type, 1 written post-constructor, 2 duplicates"
  - "Merged L-13/L-14 into existing stETH rounding entry with cross-reference"
  - "Merged M-5/M-6/L-19 into single SafeERC20 entry per discretion"
  - "Merged NC-6/NC-34 and NC-10/NC-33 per discretion (same concern)"

patterns-established:
  - "KNOWN-ISSUES.md entry format: title + what tool flags + why intentional, 2-3 sentences, detector ID in parens"

requirements-completed: [BOT-03]

# Metrics
duration: 4min
completed: 2026-03-27
---

# Phase 134 Plan 01: KNOWN-ISSUES Consolidation Summary

**KNOWN-ISSUES.md expanded from 5 to 30+ entries with all Slither/4naly3er DOCUMENT findings, 5 ERC-20 deviations, and event audit summary. GAS-10 review found all 10 candidates are false positives.**

## Performance

- **Duration:** 4 min
- **Started:** 2026-03-27T17:30:35Z
- **Completed:** 2026-03-27T17:35:09Z
- **Tasks:** 2
- **Files modified:** 3

## Accomplishments
- KNOWN-ISSUES.md restructured into 5 sections: Intentional Design, Design Mechanics, Automated Tool Findings (22 grouped entries), ERC-20 Deviations (5 entries), Event Design Decisions
- Every entry includes detector ID per D-03 (e.g., `arbitrary-send-eth`, `[M-2]`, `[GAS-7]`)
- Stats line added per D-08: tool versions + triage counts
- GAS-10 immutable review: all 10 reported instances are false positives (6 already immutable, 1 string type, 1 mutated post-constructor, 2 report duplicates)
- Dead code `_lootboxBpsToTier` removed from DegenerusGameStorage.sol (pending contract commit approval)

## Task Commits

Each task was committed atomically:

1. **Task 1: Expand KNOWN-ISSUES.md with all DOCUMENT findings + remove dead code** - `9aadd323` (feat) -- KNOWN-ISSUES.md only; contract change pending approval
2. **Task 2: GAS-10 immutable candidate review** - `13a8d7db` (docs)

**Plan metadata:** (included below)

## Files Created/Modified
- `KNOWN-ISSUES.md` - Expanded from 5 to 30+ pre-disclosure entries for C4A wardens
- `audit/gas10-immutable-candidates.md` - GAS-10 review table showing all 10 are FP
- `contracts/storage/DegenerusGameStorage.sol` - Dead code `_lootboxBpsToTier` removed (uncommitted, pending user approval per contract commit guard)

## Decisions Made
- GAS-10 reclassified from DOCUMENT to FALSE-POSITIVE after case-by-case review
- L-13/L-14 (rounding/precision) merged and cross-referenced with existing stETH rounding entry
- M-5/M-6/L-19 (SafeERC20) merged into single entry per discretion (same concern)
- NC-6/NC-34 (magic numbers) and NC-10/NC-33 (event indexed fields) merged per discretion

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] GAS-10 candidates all false positives**
- **Found during:** Task 2 (GAS-10 review)
- **Issue:** Plan expected 8-10 valid immutable candidates. Actual review found all 10 are FP (6 already immutable, 1 string type, 1 mutated post-constructor).
- **Fix:** Created review table documenting each FP. No code changes needed.
- **Files modified:** audit/gas10-immutable-candidates.md
- **Committed in:** 13a8d7db

**2. [Rule 3 - Blocking] Contract commit guard blocked dead code removal**
- **Found during:** Task 1 (dead code removal)
- **Issue:** `contracts/storage/DegenerusGameStorage.sol` change blocked by pre-commit hook requiring explicit user approval for contract modifications.
- **Fix:** Committed KNOWN-ISSUES.md separately. Contract change remains unstaged for user review.
- **Files modified:** contracts/storage/DegenerusGameStorage.sol (uncommitted)
- **Committed in:** N/A -- requires `CONTRACTS_COMMIT_APPROVED=1`

---

**Total deviations:** 2 (1 finding correction, 1 blocking policy)
**Impact on plan:** GAS-10 review completed faster since no candidates needed approval. Contract dead code removal is ready but awaits user approval per project policy.

## Issues Encountered
- Worktree was behind main branch -- fast-forward merge required to access audit/ files
- 4naly3er report contained duplicate entries for DegenerusVault (symbol and totalSupply each listed twice)

## Known Stubs

None -- all entries are fully populated with real data from audit sources.

## Next Phase Readiness
- KNOWN-ISSUES.md is complete for C4A submission
- Dead code removal in DegenerusGameStorage.sol needs user approval to commit
- Phase 134 Plan 02 can proceed (scope.txt + final checks)

---
*Phase: 134-consolidation*
*Completed: 2026-03-27*
