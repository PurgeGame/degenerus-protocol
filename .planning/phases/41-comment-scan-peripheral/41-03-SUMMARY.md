---
phase: 41-comment-scan-peripheral
plan: 03
subsystem: audit
tags: [solidity, natspec, comment-audit, deity-pass, trait-utils, icons, contract-addresses]

# Dependency graph
requires:
  - phase: 35-peripheral-contracts
    provides: "v3.1 baseline findings CMT-059 through CMT-080"
provides:
  - "Comment audit findings for DeityPass, TraitUtils, DeityBoonViewer, ContractAddresses, Icons32Data"
  - "CMT-079 NOT FIXED status confirmation"
  - "CMT-080 FIXED status confirmation"
affects: [36-consolidated-findings]

# Tech tracking
tech-stack:
  added: []
  patterns: [flag-only-audit, fresh-eyes-verification]

key-files:
  created:
    - .planning/phases/41-comment-scan-peripheral/41-03-SUMMARY.md
  modified: []

key-decisions:
  - "CMT-079 (ContractAddresses 'zeroed in source' comment) confirmed NOT FIXED despite research claiming it was -- documented as still-open finding"
  - "CMT-080 (Icons32Data _diamond phantom reference) confirmed FIXED via working tree diff"
  - "Three unchanged contracts (DeityPass, TraitUtils, DeityBoonViewer) verified clean with fresh-eyes pass -- 0 new findings"

patterns-established:
  - "Fast-track verification: unchanged contracts with 0 v3.1 findings get full read-through but expect 0 new findings"

requirements-completed: [CMT-05]

# Metrics
duration: 8min
completed: 2026-03-19
---

# Phase 41 Plan 03: Remaining/Utility Contracts Comment Audit Summary

**Fresh-eyes comment audit of 5 remaining contracts (1,009 lines): 3 unchanged contracts verified clean, CMT-080 fix confirmed, CMT-079 confirmed NOT FIXED**

## Performance

- **Duration:** 8 min
- **Started:** 2026-03-19T13:24:28Z
- **Completed:** 2026-03-19T13:32:00Z
- **Tasks:** 1
- **Files modified:** 1

## Accomplishments
- Verified DegenerusDeityPass.sol (392 lines), DegenerusTraitUtils.sol (183 lines), and DeityBoonViewer.sol (171 lines) remain unchanged and clean -- 0 new findings
- Confirmed CMT-080 fix in Icons32Data.sol: `_diamond` phantom reference successfully removed from block comment
- Discovered CMT-079 is NOT FIXED in ContractAddresses.sol: "All addresses are zeroed in source" comment still present at line 5

## Task Commits

Each task was committed atomically:

1. **Task 1: Audit all 5 remaining/utility contracts** - `b4376fc2` (docs)

**Plan metadata:** `pending` (docs: complete plan)

## Files Created/Modified
- `.planning/phases/41-comment-scan-peripheral/41-03-SUMMARY.md` - Comment audit findings for 5 remaining/utility contracts

## Decisions Made
- CMT-079 was reported as "FIXED" in research, but working tree audit confirms the "All addresses are zeroed in source" comment is still present at ContractAddresses.sol:5. Documented as NOT FIXED.
- No new CMT-series findings needed beyond the still-open CMT-079.

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
- Research incorrectly reported CMT-079 as FIXED. The actual working tree shows the comment is still present. This discrepancy was caught during execution and documented accurately.

## User Setup Required

None - no external service configuration required.

---

## DegenerusDeityPass.sol

**Scope:** 392 lines | 13 NatSpec tags | ~40 comment lines | 20 external/public functions
**Changes since v3.1:** 0 lines changed
**v3.1 findings:** 0 (none found)
**v3.2 verdict:** CLEAN -- no findings

### Findings

No new findings identified. Contract unchanged since v3.1 fresh-eyes pass.

**Fresh-eyes verification details:**
- `IDeityPassRendererV1` interface NatSpec: `@notice Optional external renderer interface (v1)` and `@dev Calls are bounded and always fallback to internal renderer on failure` -- verified accurate against `_tryRenderExternal` try/catch implementation
- Contract title `@notice Soulbound ERC721 for deity passes. 32 tokens max (one per symbol). Transfers are permanently disabled. tokenId = symbolId (0-31).` -- verified: `mint()` checks `tokenId >= 32`, all transfer/approve functions revert `Soulbound()`
- `setRenderer` `@notice Set optional external renderer. Set to address(0) to disable.` -- verified: renderer address checked in `tokenURI`
- `setRenderColors` `@param` tags for outlineColor, backgroundColor, nonCryptoSymbolColor -- all match function parameters
- `renderColors` `@notice Read active render colors.` -- returns all 3 stored color strings
- `tokenURI` `@dev Uses internal renderer by default; optional external renderer can override but never break tokenURI due to bounded staticcall + fallback.` -- verified: try/catch in `_tryRenderExternal` with fallback to internal SVG
- `mint` `@notice Mint a deity pass. Only callable by the game contract during purchase.` -- verified: checks `msg.sender != ContractAddresses.GAME`
- Section headers (Errors, Events, Storage, ERC721 Metadata, ERC165, ERC721 Views, ERC721 Mutations, Game-Only Mint) -- all accurately reflect their contents
- All 5 soulbound mutation functions (approve, setApprovalForAll, transferFrom, 2x safeTransferFrom) correctly revert `Soulbound()` matching the "soulbound -- all transfers blocked" section header

---

## DegenerusTraitUtils.sol

**Scope:** 183 lines | 17 NatSpec tags | ~49 comment lines + ~92 block comment lines | 3 functions
**Changes since v3.1:** 0 lines changed
**v3.1 findings:** 0 (none found)
**v3.2 verdict:** CLEAN -- no findings

### Findings

No new findings identified. Contract unchanged since v3.1 fresh-eyes pass.

**Fresh-eyes verification details:**
- Block comment trait system overview (lines 4-82): Extensive and accurate documentation
  - "8 bits per trait" with `[QQ][CCC][SSS]` format -- verified: `traitFromWord` returns 6-bit value `(category << 3) | sub`, caller adds 2-bit quadrant in `packedTraitsFromSeed`
  - Packed traits `[DDDDDDDD][CCCCCCCC][BBBBBBBB][AAAAAAAA]` -- verified: `packedTraitsFromSeed` packs A at bits 0-7, B at 8-15, C at 16-23, D at 24-31
  - Weighted distribution table (buckets 0-7 with widths 10,10,10,10,9,9,9,8 totaling 75) -- verified: matches `weightedBucket` thresholds at 10,20,30,40,49,58,67
  - Random seed usage: bits [63:0] for Trait A through bits [255:192] for Trait D -- verified: `uint64(rand)`, `uint64(rand >> 64)`, etc.
  - Security: "No state reads/writes - purely computational" -- verified: all functions are `internal pure`
  - "Uses uint64 intermediate to prevent truncation" -- verified: `uint32((uint64(rnd) * 75) >> 32)` at line 116
- `@title DegenerusTraitUtils`, `@author Burnie Degenerus`, `@notice Pure library for deterministic trait generation` -- accurate
- `weightedBucket` NatSpec bucket thresholds (lines 102-110) match implementation exactly
- `traitFromWord` NatSpec: "6-bit trait ID" -- accurate (category << 3 | sub gives 0-63)
- `packedTraitsFromSeed` NatSpec: seed usage bit ranges match implementation shifts
- Inline comments on each line of `packedTraitsFromSeed` (lines 174-177) accurately describe quadrant bits

---

## DeityBoonViewer.sol

**Scope:** 171 lines | 8 NatSpec tags | ~13 comment lines | 3 functions (1 external, 2 private)
**Changes since v3.1:** 0 lines changed
**v3.1 findings:** 0 (none found)
**v3.2 verdict:** CLEAN -- no findings

### Findings

No new findings identified. Contract unchanged since v3.1 fresh-eyes pass.

**Fresh-eyes verification details:**
- `@title DeityBoonViewer`, `@notice Standalone view contract for computing deity boon slot types. Reads raw state from DegenerusGame.deityBoonData() and applies the weighted random selection logic` -- verified: calls `IDeityBoonDataSource(game).deityBoonData(deity)` and runs weighted selection via `_boonFromRoll`
- `deityBoonSlots` parameter NatSpec: `@param game Address of the DegenerusGame contract` and `@param deity The deity address to query` -- match function signature
- `deityBoonSlots` return NatSpec: `@return slots Array of 3 boon type IDs for today's slots`, `@return usedMask Bitmask of slots already used today`, `@return day Current day index` -- all match `uint8[3] memory slots, uint8 usedMask, uint48 day` return types
- Weight constant verification: W_TOTAL = 1298, W_TOTAL_NO_DECIMATOR = 1248 (1298 - 50 decimator weights [40+8+2]), W_DEITY_PASS_ALL = 40 (28+10+2) -- all arithmetic verified correct
- `_boonFromRoll` private helper: no NatSpec expected, weighted selection logic correctly handles `decimatorAllowed` and `deityEligible` conditional sections
- Boon type ID constants (23 constants, lines 23-47) -- inline comments identify each boon type category accurately
- Weight constants (24 constants, lines 50-76) -- naming convention matches boon types consistently

---

## ContractAddresses.sol

**Scope:** 39 lines | 0 NatSpec tags | 4 comment lines
**Changes since v3.1:** Address values changed (test deploy), comment NOT updated
**v3.1 findings status:** CMT-079 -- verified NOT FIXED
**v3.2 verdict:** 1 finding (CMT-079 remains open)

### Findings

**CMT-079 remains open.** The v3.1 finding has not been addressed.

Lines 4-6 read:
```
// Compile-time constants populated by the deploy script.
// All addresses are zeroed in source; the deploy pipeline generates
// a concrete version with live addresses before compilation.
```

The claim "All addresses are zeroed in source" is inaccurate. All 27 address constants contain non-zero values (test/deploy addresses). The `DEPLOY_DAY_BOUNDARY` is 0 in the committed version and 20530 in the working tree. The `VRF_KEY_HASH` is a non-zero placeholder value.

This finding was originally reported as CMT-079 in v3.1. The research for v3.2 incorrectly reported it as FIXED, but the working tree confirms the comment is still present and still inaccurate.

**Original v3.1 suggestion (still applicable):** Either zero out all addresses to match the comment (making this the true source template), or update the comment to reflect the current state: "Compile-time constants. These addresses are set to test/deploy values; the deploy pipeline may regenerate this file with environment-specific addresses before compilation."

---

## Icons32Data.sol

**Scope:** 226 lines | 48 NatSpec tags | ~68 comment lines + ~73 block comment lines | 5 functions
**Changes since v3.1:** 2 lines removed (CMT-080 fix: `_diamond` phantom reference deleted)
**v3.1 findings status:** CMT-080 -- verified FIXED
**v3.2 verdict:** CLEAN -- no findings

### Findings

No new findings identified. CMT-080 fix verified complete.

**CMT-080 fix verification:**
- v3.1 reported: Block comment referenced nonexistent `_diamond` storage variable ("_diamond -\u25ba Flame icon: Center glyph for all token renders")
- v3.2 status: Line removed from block comment. `grep _diamond contracts/Icons32Data.sol` returns 0 matches.
- Working tree diff confirms: 2 lines removed (the `_diamond` line and its trailing blank line)

**Fresh-eyes verification of remaining comments:**
- Block comment architecture overview (lines 6-80): All claims verified
  - "33 icon paths" -- `string[33] private _paths` at line 111. Correct.
  - "32 quadrant symbols + 1 affiliate badge" -- paths[0-31] for symbols, paths[32] for badge. Correct.
  - Icon index layout: Q0 Crypto (0-7), Q1 Zodiac (8-15), Q2 Cards (16-23), Q3 Dice (24-31), affiliate (32) -- matches `data()` and `symbol()` functions
  - Symbol arrays `_symQ1`, `_symQ2`, `_symQ3` for quadrants 0-2 -- match storage declarations
  - "Q4 Dice names are generated dynamically" -- matches `symbol()` which returns "" for quadrant >= 3
  - Security: "Only ContractAddresses.CREATOR can call setter functions" -- verified in `setPaths`, `setSymbols`, `finalize`
  - "Batch size limited to 10 paths per call" -- verified: `if (paths.length > 10) revert MaxBatch()`
- `setPaths` NatSpec (lines 143-150): All `@param`, `@custom:reverts` tags match implementation
- `setSymbols` NatSpec (lines 162-168): `@param quadrant` description "0=Crypto, 1=Zodiac, 2=Cards" matches implementation. All reverts documented.
- `finalize` NatSpec (lines 190-193): Accurate -- CREATOR-only, once-only.
- `data` NatSpec (lines 204-208): `@param i Icon index: 0-31 for quadrant symbols, 32 for affiliate badge` -- accurate
- `symbol` NatSpec (lines 213-218): `@dev Quadrant 3 (Dice) returns empty string; renderer generates "1..8" dynamically` -- matches implementation at line 224

---

## Plan 03 Summary

| Contract | Lines | Changes | v3.1 Status | New Findings | Total |
|----------|-------|---------|-------------|--------------|-------|
| DegenerusDeityPass.sol | 392 | 0 | 0 findings | 0 | 0 |
| DegenerusTraitUtils.sol | 183 | 0 | 0 findings | 0 | 0 |
| DeityBoonViewer.sol | 171 | 0 | 0 findings | 0 | 0 |
| ContractAddresses.sol | 39 | comment unchanged | CMT-079 NOT FIXED | 0 | 1 (open) |
| Icons32Data.sol | 226 | 2 lines removed | CMT-080 FIXED | 0 | 0 |
| **Total** | **1,011** | **2** | **1 open, 1 fixed** | **0** | **1** |

**v3.1 findings disposition:**
- CMT-079 (ContractAddresses.sol:5 "zeroed in source"): NOT FIXED -- comment still present and inaccurate
- CMT-080 (Icons32Data.sol:28 `_diamond` phantom reference): FIXED -- line removed from block comment

## Next Phase Readiness
- All 5 remaining/utility contracts in CMT-05 scope have been audited
- CMT-079 remains the only open finding from this group -- carry forward to consolidated findings
- Phase 41 comment scan is now complete across all 3 plans

## Self-Check: PASSED

- FOUND: `.planning/phases/41-comment-scan-peripheral/41-03-SUMMARY.md`
- FOUND: commit `b4376fc2`
- PASS: 0 .sol files modified in commit
- PASS: 5 contract sections present

---
*Phase: 41-comment-scan-peripheral*
*Completed: 2026-03-19*
