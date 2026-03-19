# Phase 32: Game Modules Batch A - Research

**Researched:** 2026-03-18
**Domain:** Solidity NatSpec/inline comment verification + intent drift detection for 7 game module contracts
**Confidence:** HIGH

## Summary

Phase 32 audits the NatSpec and inline comments of 7 game module contracts totaling 5,505 lines: DegenerusGameMintModule.sol (1,193 lines), DegenerusGameDegeneretteModule.sol (1,179 lines), DegenerusGameWhaleModule.sol (840 lines), DegenerusGameBoonModule.sol (359 lines), DegenerusGameLootboxModule.sol (1,778 lines), DegenerusGamePayoutUtils.sol (94 lines), and DegenerusGameMintStreakUtils.sol (62 lines). The deliverable is a per-batch findings file listing every comment inaccuracy and intent drift item, each with what/why/suggestion. No code changes are made.

Two of the 7 contracts were modified after Phase 29: WhaleModule received 2 commits (3542e227 blocking lazy pass at x99 levels and updating NatSpec, 9aff84b2 limiting boon discount to first bundle and gating x99 single buys), and MintModule received 1 commit (93708354 removing the last-purchase-day lootbox block). The other 5 contracts (DegeneretteModule, BoonModule, LootboxModule, PayoutUtils, MintStreakUtils) have NOT been modified since Phase 29. Pre-identified issues during research include: orphaned NatSpec in MintModule (lines 1140-1146, function body removed but NatSpec left), orphaned NatSpec in DegeneretteModule (line 406, stale from removed function), a 260% vs 255% discrepancy in LootboxModule (line 328), and a misleading "Tickets always start at x1" in WhaleModule (line 166).

**Primary recommendation:** Split work into 3-4 plans by contract grouping. The two smallest contracts (PayoutUtils at 94 lines, MintStreakUtils at 62 lines) should be combined with the smaller module (BoonModule at 359 lines) in one plan. WhaleModule (840 lines, post-Phase-29 changes) and MintModule (1,193 lines, post-Phase-29 changes) should each get their own plans or be combined given changes. DegeneretteModule (1,179 lines) and LootboxModule (1,778 lines) are the largest and require the most careful review.

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| CMT-02 | All NatSpec and inline comments in game modules batch A (MintModule, DegeneretteModule, WhaleModule, BoonModule, LootboxModule, PayoutUtils, MintStreakUtils) are accurate and warden-ready | 5,505 total lines across 7 contracts. 626 NatSpec tags total, ~1,177 comment lines, 98 functions. 2 contracts modified post-Phase-29 (WhaleModule, MintModule). At least 4 pre-identified comment inaccuracies found during research. All contracts are delegatecall modules operating on DegenerusGameStorage. |
| DRIFT-02 | Game modules batch A reviewed for vestigial logic, unnecessary restrictions, and intent drift | Key areas to check: (1) MintModule orphaned NatSpec from removed function at end of file (lines 1140-1193), (2) DegeneretteModule orphaned NatSpec line 406 from removed affiliate credit function, (3) WhaleModule post-Phase-29 pricing changes, (4) any vestigial references to removed features across all 7 contracts, (5) BoonModule/LootboxModule boon system consistency. |
</phase_requirements>

## Standard Stack

This phase does not introduce any libraries or tools. It is a purely manual audit task using existing project infrastructure.

### Core
| Tool | Purpose | Why Standard |
|------|---------|--------------|
| Solidity source files | Primary verification target | contracts/modules/ directory is source of truth (per project memory: NEVER read from degenerus-contracts/ or testing/contracts/) |
| Phase 31 findings file | Pattern reference for findings format | audit/v3.1-findings-31-core-game-contracts.md establishes CMT/DRIFT numbering, severity conventions, and format |
| Git history | Identify post-Phase-29 changes | Commits 3542e227, 9aff84b2 (WhaleModule) and 93708354 (MintModule) changed contracts after Phase 29 |

### Ground Truth Sources (for cross-reference)
| Source | Location | What It Proves |
|--------|----------|---------------|
| Phase 31 findings | audit/v3.1-findings-31-core-game-contracts.md | Established format: CMT-NNN / DRIFT-NNN numbering, what/where/why/suggestion/category/severity fields |
| Phase 29 verification | .planning/phases/29-comment-documentation-correctness/29-VERIFICATION.md | What Phase 29 already verified |
| KNOWN-ISSUES.md | audit/KNOWN-ISSUES.md | Design decisions documented for wardens |
| PAYOUT-SPECIFICATION.html | audit/PAYOUT-SPECIFICATION.html | Comprehensive payout flow reference |

## Architecture Patterns

### Contract File Inventory (by size, for work ordering)

```
contracts/modules/DegenerusGameLootboxModule.sol       1,778 lines  (308 NatSpec tags, ~408 comment lines, 27 functions)
contracts/modules/DegenerusGameMintModule.sol          1,193 lines  (47 NatSpec tags, ~208 comment lines, 16 functions) [POST-PHASE-29 CHANGES]
contracts/modules/DegenerusGameDegeneretteModule.sol   1,179 lines  (156 NatSpec tags, ~333 comment lines, 31 functions)
contracts/modules/DegenerusGameWhaleModule.sol           840 lines  (85 NatSpec tags, ~179 comment lines, 14 functions) [POST-PHASE-29 CHANGES]
contracts/modules/DegenerusGameBoonModule.sol            359 lines  (18 NatSpec tags, ~35 comment lines, 5 functions)
contracts/modules/DegenerusGamePayoutUtils.sol            94 lines  (7 NatSpec tags, ~8 comment lines, 3 functions)
contracts/modules/DegenerusGameMintStreakUtils.sol         62 lines  (5 NatSpec tags, ~6 comment lines, 2 functions)
                                                       -----
Total:                                                 5,505 lines  (626 NatSpec tags, ~1,177 comment lines, 98 functions)
```

### Post-Phase-29 Code Changes (Critical Context)

Two contracts were modified after Phase 29 completed:

| Contract | Commit | Changes | Impact on Comments |
|----------|--------|---------|--------------------|
| WhaleModule | 3542e227 | Blocked lazy pass at x99 levels, fixed stale NatSpec | NatSpec for `purchaseLazyPass` was updated (x99 exclusion added). The `@custom:reverts` tag was updated. Code changed to add `currentLevel % 100 == 99` guard. |
| WhaleModule | 9aff84b2 | Limited boon discount to first bundle only, gated x99 single buys | Pricing comment updated ("boon discount applies to first bundle only"). New x99 guard added with inline comment. The `@dev` for `WHALE_BUNDLE_STANDARD_PRICE` was updated from "x49/x99 levels" to "levels 4+". |
| MintModule | 93708354 | Removed last-purchase-day lootbox block | Two lines removed (block + comment). No stale comment left behind from this change. |

The other 5 contracts (DegeneretteModule, BoonModule, LootboxModule, PayoutUtils, MintStreakUtils): NO changes since Phase 29.

### Pre-Identified Issues (Found During Research)

These are confirmed issues found while reading the contracts during research:

| Contract | Line(s) | Issue | Category |
|----------|---------|-------|----------|
| MintModule | 1140-1146 | Orphaned NatSpec -- `@notice Resolve a lootbox directly (decimator claims)...` with 6 NatSpec lines but no function body. Lines 1147-1192 are empty. The function was removed but the NatSpec was left behind. A NatSpec parser would associate these tags with nothing or with the closing `}`. | CMT |
| DegeneretteModule | 406 | Orphaned NatSpec -- `@notice Places Full Ticket bets using pending affiliate Degenerette credit.` appears immediately before the unrelated `resolveBets` function. This NatSpec belongs to a removed function but was left behind, identical to the CMT-010 pattern from Phase 31. | CMT |
| LootboxModule | 328 | Comment says `Maximum EV at 260%+ activity (135%)` but `ACTIVITY_SCORE_MAX_BPS = 25_500` which is 255%, not 260%. Line 322 correctly says "255%+". The same function's NatSpec at line 467 correctly says "255%+ activity". Only line 328 is wrong. | CMT |
| WhaleModule | 166 | NatSpec says `Tickets always start at x1` but `ticketStartLevel = passLevel` (line 211) where `passLevel = level + 1` (line 192). Tickets start at whatever level+1 is, not necessarily at a level ending in 1. The "x1" notation is misleading. | CMT |
| MintModule | 294-296 | `processFutureTicketBatch` -- a significant external function with no NatSpec whatsoever (no @notice, @dev, @param, or @return). This function processes the ticket activation queue and is callable externally. | CMT (missing NatSpec) |

### Verification Methodology for v3.1

Same methodology as Phase 31, adapted for module contracts:

**CMT-02 approach (comment accuracy):**
1. For each contract, read every NatSpec tag (@notice, @dev, @param, @return, @custom) and every inline // comment
2. For each comment, verify it matches actual code behavior in the current HEAD
3. Focus on warden-readability: "Would a C4A warden reading this be misled?"
4. Flag any mismatch as a finding with what/why/suggestion
5. Pay special attention to cross-module references (these modules call each other via delegatecall)

**DRIFT-02 approach (intent drift):**
1. Scan for vestigial references to removed features
2. Check for guards/conditions that may have become unnecessary after code changes
3. Look for logic whose behavior has changed but whose surrounding commentary still describes old behavior
4. Check for orphaned NatSpec from removed functions (pattern from CMT-010 in Phase 31)
5. Flag any drift as a finding with what/why/suggestion

**Findings file format (continuing Phase 31 numbering):**

Phase 31 ended at CMT-010 and DRIFT-002. Phase 32 findings should continue the sequence:
- CMT findings: CMT-011, CMT-012, ...
- DRIFT findings: DRIFT-003, DRIFT-004, ...

```markdown
# Phase 32 Findings: Game Modules Batch A

**Date:** 2026-03-18
**Scope:** MintModule, DegeneretteModule, WhaleModule, BoonModule, LootboxModule, PayoutUtils, MintStreakUtils
**Pass:** v3.1 second independent review (v3.0 Phase 29 was first pass)
**Mode:** Flag-only -- no code changes

## Summary

| Contract | CMT findings | DRIFT findings | Total |
|----------|-------------|----------------|-------|
| DegenerusGameMintModule.sol | X | Y | Z |
| DegenerusGameDegeneretteModule.sol | X | Y | Z |
| DegenerusGameWhaleModule.sol | X | Y | Z |
| DegenerusGameBoonModule.sol | X | Y | Z |
| DegenerusGameLootboxModule.sol | X | Y | Z |
| DegenerusGamePayoutUtils.sol | X | Y | Z |
| DegenerusGameMintStreakUtils.sol | X | Y | Z |
| **Total** | **X** | **Y** | **Z** |

## [Contract] Findings

### CMT-0NN: [Brief title]
- **What:** [The specific comment inaccuracy]
- **Where:** [File:Line]
- **Why:** [Why a warden would be misled]
- **Suggestion:** [Recommended fix]
- **Category:** comment-inaccuracy | intent-drift
- **Severity:** INFO | LOW
```

### Anti-Patterns to Avoid

- **Rubber-stamping Phase 29 verdicts for unchanged contracts:** Phase 29 results provide useful context but v3.1 should still perform an independent review with fresh eyes focused on warden-readability.
- **Missing orphaned NatSpec:** The two orphaned NatSpec instances found in research (MintModule line 1140, DegeneretteModule line 406) follow the exact pattern of CMT-010 from Phase 31. The reviewer must actively scan for detached NatSpec tags that may have been left behind when functions were removed.
- **Overlooking missing NatSpec on external functions:** `processFutureTicketBatch` in MintModule has zero NatSpec despite being a significant external function. Missing NatSpec is as much a warden-readability issue as wrong NatSpec.
- **Scale confusion (BPS vs PPM):** WhaleModule uses both BPS (/10000) and PPM (/1000000) for DGNRS pool calculations. LootboxModule uses BPS extensively but also BOON_PPM_SCALE (1e6) for boon probability rolls. Verify each percentage comment against its denominator.
- **Ignoring block comments and section headers:** DegeneretteModule has extensive packed bet layout documentation (lines 312-341). WhaleModule has extensive @dev blocks on purchase functions. These are prime warden reading material.
- **Scope creep into code fixes:** If a real bug or optimization is found, document it as a finding but do NOT attempt code changes. This is flag-only.
- **Missing cross-module delegatecall NatSpec accuracy:** Several modules delegatecall into each other (LootboxModule calls BoonModule, DegeneretteModule calls LootboxModule). Verify that NatSpec accurately describes the delegatecall context.

### Module Inheritance/Dependency Structure

Understanding the inheritance hierarchy is critical for verifying NatSpec accuracy:

```
DegenerusGameStorage (abstract)
  |
  +-- DegenerusGameBoonModule (standalone)
  |
  +-- DegenerusGameLootboxModule (standalone)
  |
  +-- DegenerusGameMintModule (standalone)
  |
  +-- DegenerusGamePayoutUtils (abstract)
  |     |
  |     +-- DegenerusGameMintStreakUtils (abstract)
  |           |
  |           +-- DegenerusGameDegeneretteModule (concrete)
  |           |
  |           +-- DegenerusGameWhaleModule (concrete)
```

Key implications for NatSpec review:
- PayoutUtils and MintStreakUtils are abstract -- their NatSpec describes helpers used by DegeneretteModule and WhaleModule
- BoonModule and LootboxModule are standalone modules called via nested delegatecall
- All modules operate on DegenerusGameStorage via delegatecall from DegenerusGame

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Finding post-Phase-29 changes | Manual git log | `git diff bd910dd0..HEAD -- contracts/modules/DegenerusGameWhaleModule.sol` | Precise diff of what changed after Phase 29 |
| Counting NatSpec tags | Manual counting | `grep -cE '@dev\|@notice\|@param\|@return' contracts/modules/File.sol` | Accurate enumeration |
| Finding orphaned NatSpec | Reading all comments manually | `grep -n '/// @notice\|/// @dev' FILE \| diff with function declarations` | Quick identification of detached NatSpec |
| Verifying percentages against constants | Mental math | `grep -n 'BPS\|PPM' FILE` to list all scale constants, then verify each % comment | Catches BPS/PPM scale confusion |

## Common Pitfalls

### Pitfall 1: Orphaned NatSpec from Removed Functions
**What goes wrong:** NatSpec comments left behind when a function body is removed, creating misleading documentation
**Why it happens:** Developers remove function bodies but leave the NatSpec, or cut-paste errors during refactoring
**How to avoid:** For every NatSpec block, verify it is immediately followed by a function/variable declaration. Lines 1140-1146 of MintModule and line 406 of DegeneretteModule are confirmed instances.
**Warning signs:** NatSpec tags followed by blank lines, other NatSpec tags, or unrelated declarations.

### Pitfall 2: Scale Confusion (BPS vs PPM)
**What goes wrong:** A comment says a percentage but the constant uses a different scale
**Why it happens:** The codebase uses BPS (/10000), half-BPS (/20000), and PPM (/1000000)
**How to avoid:** For every percentage in a comment, verify the denominator. WhaleModule uses PPM for DGNRS pool calculations. LootboxModule uses PPM for boon probability. DegeneretteModule uses BPS for ROI.
**Warning signs:** Constants like `PPM = 10` (0.001%) vs comment saying "0.01%".

### Pitfall 3: Assuming NatSpec Updates in Post-Phase-29 Commits
**What goes wrong:** Assuming that the commits that changed WhaleModule (3542e227, 9aff84b2) also updated all relevant NatSpec
**Why it happens:** The commit messages say "fix stale NatSpec" but may have only fixed the most obvious issues
**How to avoid:** Re-verify ALL NatSpec in WhaleModule, not just the lines touched by the commits. The WhaleModule `purchaseWhaleBundle` NatSpec at line 166 ("Tickets always start at x1") was NOT updated.
**Warning signs:** Stale NatSpec that is close to but not on lines touched by recent commits.

### Pitfall 4: Missing NatSpec on External Functions
**What goes wrong:** Focusing only on wrong NatSpec and missing functions with NO NatSpec at all
**Why it happens:** It is easier to check existing NatSpec for accuracy than to notice its absence
**How to avoid:** List all external/public functions and verify each has at minimum @notice and @param tags. `processFutureTicketBatch` in MintModule is the confirmed missing case.
**Warning signs:** `function foo(` with no `///` lines above it.

### Pitfall 5: Overlapping Constants Across Modules
**What goes wrong:** Two modules define the same constant with the same name but different NatSpec descriptions
**Why it happens:** Modules are independently compiled and may duplicate constants for EIP-170 size reasons
**How to avoid:** Check that duplicate constants (e.g., LOOTBOX_BOOST_5_BONUS_BPS appears in MintModule, WhaleModule, and LootboxModule) have consistent NatSpec descriptions.
**Warning signs:** Same constant name in multiple files with different `@dev` descriptions.

## Code Examples

### Identifying Post-Phase-29 Changes

```bash
# What changed in modules after Phase 29 completed (bd910dd0)
git diff bd910dd0..HEAD -- contracts/modules/DegenerusGameWhaleModule.sol
git diff bd910dd0..HEAD -- contracts/modules/DegenerusGameMintModule.sol

# Verify other 5 modules have NOT changed
git diff bd910dd0..HEAD -- contracts/modules/DegenerusGameDegeneretteModule.sol
# (empty = no changes)
```

### Finding Orphaned NatSpec

```bash
# Look for NatSpec followed by blank lines (orphaned pattern)
grep -n -A1 '/// @' contracts/modules/DegenerusGameMintModule.sol | grep -B1 '^--$\|^[0-9]*-$'

# Check end of MintModule for orphaned NatSpec area
tail -60 contracts/modules/DegenerusGameMintModule.sol
```

### Verifying Percentage Comments Against Constants

```bash
# List all BPS/PPM constants in a module
grep -n 'private constant.*BPS\|private constant.*PPM' contracts/modules/DegenerusGameLootboxModule.sol
# Then verify each associated @dev comment matches the actual percentage
```

## State of the Art

This section is not applicable to a documentation verification phase. No libraries, frameworks, or evolving standards are involved. The Solidity 0.8.34 compiler and NatSpec specification are stable.

## Open Questions

1. **Finding numbering continuation from Phase 31**
   - What we know: Phase 31 ended at CMT-010 and DRIFT-002.
   - What's unclear: Should Phase 32 continue the sequence (CMT-011, DRIFT-003) or restart (CMT-001)?
   - Recommendation: Continue the sequence. Phase 36 will consolidate all findings, so consistent numbering across phases avoids ID collisions.

2. **Depth of review for BoonModule's repetitive pattern**
   - What we know: BoonModule consists of 4 near-identical consume functions and one large `checkAndClearExpiredBoon` function with 11 repetitive boon-clearing blocks.
   - What's unclear: How deeply to verify each repetitive block vs. pattern-checking the first and spot-checking the rest.
   - Recommendation: Verify the first block in full, then pattern-check the remaining blocks for consistent structure. Flag any block that deviates from the pattern.

3. **LootboxModule size (1,778 lines) and plan splitting**
   - What we know: LootboxModule is the largest contract in this batch, larger than DegenerusAdmin.sol from Phase 31.
   - What's unclear: Whether it should get its own dedicated plan or be combined with another contract.
   - Recommendation: Give LootboxModule its own plan. Its 308 NatSpec tags, complex boon probability math, and reward distribution logic demand focused attention.

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Manual audit verification (no automated tests) |
| Config file | N/A |
| Quick run command | N/A (documentation review, not code execution) |
| Full suite command | N/A |

### Phase Requirements -> Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| CMT-02 | NatSpec and inline comments in 7 game module contracts are accurate and warden-ready | manual-only | N/A -- requires reading and cross-referencing each comment against code | N/A |
| DRIFT-02 | Game modules batch A reviewed for vestigial logic, unnecessary restrictions, and intent drift | manual-only | N/A -- requires understanding designer intent vs actual behavior | N/A |

**Justification for manual-only:** This phase verifies the semantic accuracy of human-written English comments against code behavior and design intent. There is no automated tool that can determine whether a NatSpec description would mislead a C4A warden. The verification requires understanding the delegatecall execution context, cross-module interactions, and the protocol's intended design.

### Sampling Rate
- **Per task commit:** Review findings file for completeness -- every function and block comment in the target contract(s) should be covered
- **Per wave merge:** Cross-check that all 7 contracts are covered with no files missed
- **Phase gate:** CMT-02 and DRIFT-02 both have explicit verdicts; a per-batch findings file exists with what/why/suggestion for every item

### Wave 0 Gaps
None -- no test infrastructure needed. This is a documentation/findings-only audit phase producing a findings markdown file.

## Sources

### Primary (HIGH confidence)
- contracts/modules/DegenerusGameMintModule.sol -- 1,193 lines, read and analyzed in full
- contracts/modules/DegenerusGameDegeneretteModule.sol -- 1,179 lines, read and analyzed in full
- contracts/modules/DegenerusGameWhaleModule.sol -- 840 lines, read and analyzed in full
- contracts/modules/DegenerusGameBoonModule.sol -- 359 lines, read and analyzed in full
- contracts/modules/DegenerusGameLootboxModule.sol -- 1,778 lines, read and analyzed in full
- contracts/modules/DegenerusGamePayoutUtils.sol -- 94 lines, read and analyzed in full
- contracts/modules/DegenerusGameMintStreakUtils.sol -- 62 lines, read and analyzed in full
- git diff bd910dd0..HEAD -- verified 2 contracts changed, 5 unchanged since Phase 29
- audit/v3.1-findings-31-core-game-contracts.md -- Phase 31 findings format and numbering reference
- .planning/phases/31-core-game-contracts/31-RESEARCH.md -- Phase 31 research methodology reference

### Secondary (MEDIUM confidence)
- Phase 29 detailed audit reports recoverable via git show bd910dd0:audit/v3.0-doc-*.md -- deleted but in history
- .planning/PROJECT.md -- Key decisions table

## Metadata

**Confidence breakdown:**
- Scope assessment: HIGH -- all 7 contract files read in full, line/comment/function counts verified, post-Phase-29 changes identified via git diff
- Pre-identified issues: HIGH -- 5 potential issues found during research by direct code inspection (orphaned NatSpec x2, 260% vs 255%, misleading "x1", missing NatSpec on processFutureTicketBatch)
- Methodology: HIGH -- standard NatSpec/inline review approach proven in Phase 31, reusing established findings format
- Completeness of pre-identified issues: MEDIUM -- 5 issues found during research, but full review may find substantially more given the 626 NatSpec tags and 1,177 comment lines to verify

**Research date:** 2026-03-18
**Valid until:** 2026-04-17 (30 days -- stable domain, contracts not expected to change during audit prep)
