---
phase: 30-tooling-setup-and-static-analysis
plan: 03
subsystem: infra
tags: [halmos, symbolic-verification, formal-methods, tooling]

requires:
  - phase: 30-01
    provides: foundry.toml with deep profile sections (must be restored after Halmos)
provides:
  - Halmos 0.3.3 working configuration with documented swap procedure
  - Per-function symbolic verification results for 3 invariant test contracts
  - Phase 35 reproduction guide for full symbolic verification campaign
affects: [35]

tech-stack:
  added: []
  patterns:
    - "foundry.toml swap for Halmos (remove [fuzz]/[invariant], use --forge-build-out forge-out)"
    - "PriceLookup and BurnieCoin properties are Halmos-tractable; ShareMath properties timeout"

key-files:
  created:
    - .planning/phases/30-tooling-setup-and-static-analysis/halmos-results.md
  modified: []

key-decisions:
  - "Use --forge-build-out forge-out to resolve Halmos 'No tests found' error (default is 'out')"
  - "ShareMath timeouts are expected (256-bit bvudiv intractable) -- Foundry 10K fuzzing sufficient"
  - "vm.expectRevert ERROR in BurnieCoin is Halmos limitation, not protocol issue"

patterns-established:
  - "Halmos swap procedure: backup foundry.toml, write clean config, run, restore"
  - "testFuzz_ prefix works with --function testFuzz flag"

requirements-completed: [TOOL-04]

duration: 12min
completed: 2026-03-05
---

# Phase 30 Plan 03: Halmos Configuration Fix and Symbolic Verification Summary

**Fixed Halmos 0.3.3 configuration (--forge-build-out forge-out key discovery), verified 13/21 symbolic properties across 3 contracts, zero counterexamples**

## Performance

- **Duration:** 12 min
- **Started:** 2026-03-05T13:25:00Z
- **Completed:** 2026-03-05T13:37:00Z
- **Tasks:** 1
- **Files modified:** 1

## Accomplishments

- Identified critical `--forge-build-out forge-out` flag (project uses `forge-out`, Halmos defaults to `out`)
- PriceLookupInvariants: 8/8 properties PASS in 6.24s (full symbolic verification across entire uint24 input space)
- BurnieCoinInvariants: 5/6 properties PASS in 0.40s (1 ERROR from unsupported `vm.expectRevert` cheatcode)
- ShareMathInvariants: 7/7 TIMEOUT (256-bit bitvector division intractable for yices solver)
- Zero counterexamples found across all 13 verified properties
- Documented complete configuration procedure for Phase 35 reproduction

## Task Commits

1. **Task 1: Fix Halmos configuration and run symbolic verification** - `0a49d33` (feat)

## Files Created/Modified

- `.planning/phases/30-tooling-setup-and-static-analysis/halmos-results.md` - Per-function Halmos execution results with configuration notes

## Decisions Made

1. **--forge-build-out forge-out:** The project uses `forge-out` as its output directory, but Halmos defaults to `out`. Without this flag, Halmos reports "No tests found" despite successful compilation. This was the primary blocker.
2. **foundry.toml swap required:** Halmos 0.3.3 cannot parse [fuzz] and [invariant] TOML sections. Temporary clean foundry.toml with only build config resolves this.
3. **ShareMath timeouts are expected:** The `(reserve * amount) / supply` pattern with 128-256 bit inputs generates `bvudiv_256` SMT queries that are intractable. Phase 35 should consider input bitwidth reduction or accept Foundry 10K fuzzing as evidence.
4. **vm.expectRevert unsupported:** Halmos 0.3.3 does not implement this cheatcode. Phase 35 should exclude revert-testing functions or wrap them in Halmos-compatible `check_` functions.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] --forge-build-out flag discovery**
- **Found during:** Task 1 (initial Halmos run)
- **Issue:** Halmos reported "No tests found" despite correct contract name and function prefix
- **Fix:** Added `--forge-build-out forge-out` to match project's non-default output directory
- **Files modified:** N/A (command-line flag)
- **Verification:** Halmos successfully found and executed PriceLookupInvariantsTest
- **Committed in:** Part of 0a49d33

**2. [Rule 3 - Blocking] Contract name correction**
- **Found during:** Task 1 (initial Halmos run)
- **Issue:** Plan referenced `ShareMathInvariants` but actual contract is `ShareMathInvariantsTest`
- **Fix:** Used correct `Test` suffix in --contract flag
- **Files modified:** N/A (command-line flag)
- **Verification:** Halmos found the contract
- **Committed in:** Part of 0a49d33

---

**Total deviations:** 2 auto-fixed (2 blocking)
**Impact on plan:** Both were configuration discovery issues, resolved during execution. No scope creep.

## Issues Encountered

1. **ShareMath solver timeouts:** All 7 ShareMath properties timeout at 30-60s. Root cause is 256-bit bitvector division. Documented as expected behavior with Phase 35 recommendations.

2. **vm.expectRevert not supported:** BurnieCoin `testFuzz_vaultMintTo_revertOnExceed` errors because Halmos 0.3.3 doesn't implement this cheatcode. Documented as Halmos limitation.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- Halmos configuration verified and documented
- Phase 35 has clear guidance on which properties are tractable vs. timeout
- All Phase 30 tooling setup complete -- ready for Phase 31 (Composition) and Phase 32 (Precision)

---
*Phase: 30-tooling-setup-and-static-analysis*
*Completed: 2026-03-05*
