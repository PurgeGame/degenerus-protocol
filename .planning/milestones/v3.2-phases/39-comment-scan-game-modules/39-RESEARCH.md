# Phase 39: Comment Scan -- Game Modules - Research

**Researched:** 2026-03-19
**Domain:** Solidity NatSpec/inline/block comment verification across all 12 game module files
**Confidence:** HIGH

## Summary

Phase 39 performs a fresh comment audit across all game module files in `contracts/modules/`. The roadmap says "9 game modules" but the actual inventory is **10 concrete module contracts + 2 abstract utility contracts = 12 files totaling 11,438 lines**. All 12 files should be audited because the utilities (PayoutUtils, MintStreakUtils) are inherited by the modules and their comments directly affect warden comprehension.

The working tree contains uncommitted changes to 9 of the 12 module files. These changes fall into two categories: (1) **v3.1 comment fixes** -- the 84-finding flag-only audit from v3.1 (Phases 32-33) identified 31 comment issues across the module files, and these fixes have been applied but not committed; (2) **code changes** -- the decimator claim expiry removal (`19f5bc60`) and the rngLocked removal modified actual contract logic. The v3.2 re-scan must audit the **current working tree state** (post-fix, post-code-change), not the committed HEAD, since the working tree represents what will ship to C4A.

The v3.1 audit found 31 findings across module files (14 in Batch A, 17 in Batch B). The uncommitted diffs show those findings have been addressed. This phase's job is to verify the fixes are correct AND find any new issues introduced by: (a) the fixes themselves (e.g., new NatSpec that is itself inaccurate), (b) the decimator expiry removal code change, (c) any other code changes since v3.1. The deliverable is a fresh findings list, not a diff against v3.1.

**Primary recommendation:** Split into 3-4 plans organized by file size. The largest files (JackpotModule at 2,792 lines, AdvanceModule at 1,382 lines) should each get their own plan. Medium files (DecimatorModule 1,031, DegeneretteModule 1,178, LootboxModule 1,778, MintModule 1,149) can be grouped into 1-2 plans. Small files (BoonModule 359, EndgameModule 538, GameOverModule 232, WhaleModule 843, PayoutUtils 94, MintStreakUtils 62) can be combined into 1-2 plans.

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| CMT-01 | Game module contracts -- all NatSpec, inline, and block comments verified (9 modules) | 12 files (10 modules + 2 utilities), 11,438 total lines. 9 files have uncommitted comment fixes from v3.1. v3.1 found 31 issues in these files. All fixes applied in working tree need verification. Decimator expiry removal and other code changes create new comment drift risk. Established format: per-finding with file/line/what/why/suggestion/category/severity. |
</phase_requirements>

## Standard Stack

This phase uses no libraries or tools beyond the source files themselves. It is a manual audit task.

### Core
| Tool | Purpose | Why Standard |
|------|---------|--------------|
| Solidity source files (working tree) | Primary verification target | `contracts/modules/` directory -- MUST read from working tree (not HEAD) since it contains applied fixes |
| v3.1 findings files (from git) | Reference for what was already found and fixed | `git show HEAD:audit/v3.1-findings-32-game-modules-batch-a.md` and `v3.1-findings-33-game-modules-batch-b.md` |
| v3.1 consolidated findings | Master reference for numbering and format | `git show HEAD:audit/v3.1-findings-consolidated.md` -- 84 total findings, established CMT/DRIFT numbering |

### Ground Truth Sources (for cross-reference)
| Source | Location | What It Proves |
|--------|----------|---------------|
| PAYOUT-SPECIFICATION.html | audit/PAYOUT-SPECIFICATION.html | Comprehensive payout flow -- validates NatSpec claims about fund routing |
| KNOWN-ISSUES.md | audit/KNOWN-ISSUES.md | Design decisions documented for wardens -- avoids flagging known choices |
| ContractAddresses.sol | contracts/ContractAddresses.sol | 10 module addresses defined -- confirms module inventory |
| DegenerusGameStorage.sol | contracts/storage/DegenerusGameStorage.sol | Storage layout -- validates module storage interaction comments |

## Architecture Patterns

### File Inventory (all 12 files, by size)

```
contracts/modules/DegenerusGameJackpotModule.sol       2,792 lines  (258 NatSpec, 424 inline, 57 functions) [CHANGED]
contracts/modules/DegenerusGameLootboxModule.sol       1,778 lines  (329 NatSpec, 395 inline, 27 functions) [CHANGED]
contracts/modules/DegenerusGameAdvanceModule.sol       1,382 lines  (119 NatSpec, 203 inline, 38 functions) [CHANGED]
contracts/modules/DegenerusGameDegeneretteModule.sol   1,178 lines  (187 NatSpec, 325 inline, 31 functions) [CHANGED]
contracts/modules/DegenerusGameMintModule.sol          1,149 lines  (56 NatSpec, 143 inline, 16 functions)  [CHANGED]
contracts/modules/DegenerusGameDecimatorModule.sol     1,031 lines  (200 NatSpec, 281 inline, 32 functions) [CHANGED]
contracts/modules/DegenerusGameWhaleModule.sol           843 lines  (95 NatSpec, 122 inline, 14 functions)  [CHANGED]
contracts/modules/DegenerusGameEndgameModule.sol         538 lines  (85 NatSpec, 116 inline, 9 functions)   [CHANGED]
contracts/modules/DegenerusGameBoonModule.sol            359 lines  (21 NatSpec, 26 inline, 5 functions)    [CHANGED]
contracts/modules/DegenerusGameGameOverModule.sol        232 lines  (38 NatSpec, 46 inline, 7 functions)    [no changes]
contracts/modules/DegenerusGamePayoutUtils.sol            94 lines  (7 NatSpec, 8 inline, 3 functions)      [no changes]
contracts/modules/DegenerusGameMintStreakUtils.sol         62 lines  (5 NatSpec, 6 inline, 2 functions)     [no changes]
                                                       ------
Total:                                                 11,438 lines  (~1,400 NatSpec tags, ~2,095 inline, 241 functions)
```

**[CHANGED]** = has uncommitted working tree changes (v3.1 fixes and/or code changes)

### Module vs Utility Classification

| Type | Count | Files | Notes |
|------|-------|-------|-------|
| Concrete delegatecall modules | 10 | AdvanceModule, BoonModule, DecimatorModule, DegeneretteModule, EndgameModule, GameOverModule, JackpotModule, LootboxModule, MintModule, WhaleModule | Each has a `GAME_*_MODULE` address in ContractAddresses.sol |
| Abstract utility contracts | 2 | PayoutUtils, MintStreakUtils | Inherited by modules; not independently deployed |

The roadmap says "9 game modules" but there are 10 concrete modules. The discrepancy likely comes from counting GameOverModule as part of "core" rather than "modules," or simply a miscount. **All 12 files should be audited** because utility comments are inherited context for module auditors.

### Working Tree Changes: What Was Fixed

The uncommitted diffs contain fixes for the following v3.1 findings (verified by reading the diff):

**AdvanceModule (9 lines changed):**
- CMT-039: Module list in delegatecall header corrected -- now lists EndgameModule, JackpotModule, MintModule, GameOverModule (was missing GameOverModule, listed wrong modules)

**BoonModule (2 lines changed):**
- CMT-019: Removed "and lootbox view functions" from contract @notice

**DecimatorModule (15 lines changed):**
- CMT-031: "player burn resets" changed to "carried over to the new bucket"
- CMT-033: Added full NatSpec to TerminalDecBurnRecorded event (7 @param tags)
- CMT-034: Removed unused TerminalDecAlreadyClaimed error
- CMT-035: Constants @dev updated to include "activity cap"
- Inline comment fix: "totalBurn == 0 as claimed flag" changed to "weightedBurn is zeroed after claiming"

**DegeneretteModule (1 line removed):**
- CMT-020: Removed orphaned NatSpec line "Places Full Ticket bets using pending affiliate Degenerette credit"

**EndgameModule (12 lines changed):**
- CMT-036: "guarded by a per-level paid flag" changed to "Called once during level transition by advanceGame"
- CMT-037: "two-tier" changed to "three-tier" with proper Small/Medium/Large descriptions
- CMT-038: Simplified claimWhalePass inline comments (removed conditional description for unconditional code)

**JackpotModule (57 lines changed):**
- CMT-025: Numbering gap fixed (step 4 renumbered to step 3)
- CMT-026: payDailyJackpot NatSpec block moved to correct position above function declaration
- CMT-027: "next level or next+1 (50/50)" changed to "level+1 through level+4 (25% each)"
- CMT-028: "loot box conversion" changed to "auto-rebuy to tickets"
- CMT-029: "loot box awards (added to nextPrizePool)" changed to "auto-rebuy tickets (added to next/futurePool)"
- CMT-030: Removed orphaned NatSpec from removed loot box distribution function

**LootboxModule (8 lines changed):**
- CMT-021: "260%" changed to "255%"
- CMT-022: Removed "resolveLootboxRng" from function list in contract @dev
- CMT-023: "decimator claims" changed to "inline using a provided RNG word"
- CMT-024: Added "11=LazyPassBoon" to LootBoxReward event @param rewardType

**MintModule (70 lines changed):**
- CMT-011: Removed orphaned NatSpec + blank lines at end of file (lines 1140-1193 deleted)
- CMT-012: Added full NatSpec to processFutureTicketBatch (6 tags)
- CMT-013: RNG gating reference removed, replaced with accurate cutoff description
- CMT-014: "milestones" removed from recordMintData @dev
- CMT-015: "+10pp" inline comment replaced with accurate "+100 BURNIE per ticket for affiliates"

**WhaleModule (7 lines changed):**
- CMT-016: "Tickets always start at x1" changed to "Tickets start at the next level (level + 1)"
- CMT-017: Boon discount NatSpec now says "first bundle only; remaining bundles at standard price"
- CMT-018: Added x99 minimum 2 bundles revert to @custom:reverts

### Code Changes Requiring Comment Verification

Beyond comment fixes, these code changes may introduce new comment inaccuracies:

| Change | Commit | Impact on Comments |
|--------|--------|--------------------|
| Decimator claim expiry removal | 19f5bc60 | Claims now persist across rounds. Any comment referencing expiry windows, round-scoped claims, or TerminalDecAlreadyClaimed needs checking. The TerminalDecAlreadyClaimed error was removed in the fix diff but its removal also serves the code change. |
| rngLocked removal from coinflip claim paths | (in BurnieCoinflip, not modules) | Module comments referencing "rngLocked" gating should be verified -- particularly in AdvanceModule and MintModule if they reference RNG lock state. |

### Recommended Plan Structure

Group files by workload to keep each plan roughly equal effort:

| Plan | Files | Total Lines | Key Concern |
|------|-------|-------------|-------------|
| Plan 1 | JackpotModule (2,792) | ~2,800 | Largest file, most complex NatSpec (57 functions), 6 v3.1 fixes to verify |
| Plan 2 | DecimatorModule (1,031), DegeneretteModule (1,178), MintModule (1,149) | ~3,350 | DecimatorModule has code changes (expiry removal), all 3 had v3.1 fixes |
| Plan 3 | LootboxModule (1,778), AdvanceModule (1,382) | ~3,150 | LootboxModule is second-largest, AdvanceModule has the delegatecall module list header |
| Plan 4 | WhaleModule (843), EndgameModule (538), BoonModule (359), GameOverModule (232), PayoutUtils (94), MintStreakUtils (62) | ~2,130 | Smaller files, quick to verify, GameOverModule/PayoutUtils/MintStreakUtils have no changes |

Alternative: 3 plans (combine Plans 2+4 or 3+4), depending on desired granularity.

### Verification Methodology

For each file, the auditor must:

1. **NatSpec verification:** Read every @notice, @dev, @param, @return, @custom tag. Verify each matches actual function signature and behavior in the working tree.
2. **Inline comment verification:** Read every `//` comment. Verify it accurately describes the code it annotates.
3. **Block comment verification:** Read every `/* ... */` block and section header. Verify structural accuracy.
4. **Fix verification:** For files with v3.1 fixes, verify the fix itself is accurate (not just that the old issue is gone, but that the new text is correct).
5. **Cross-reference check:** For comments referencing other contracts or modules, verify the referenced behavior exists.

### Findings Format

Follow the v3.1 established format:

```markdown
### CMT-NNN: [Brief title]

- **What:** [Description of the inaccuracy]
- **Where:** [Filename]:[line(s)]
- **Why:** [How this would mislead a C4A warden]
- **Suggestion:** [Specific fix text]
- **Category:** comment-inaccuracy | intent-drift
- **Severity:** LOW | INFO
```

**Numbering:** v3.2 findings should use a fresh numbering sequence (CMT-V32-001, etc.) to distinguish from v3.1 findings, since many v3.1 findings have been fixed.

### Deliverable

A single findings file: `audit/v3.2-findings-39-game-modules.md` with:
- Summary table (per-contract counts)
- Per-contract sections with individual findings
- Severity classification (LOW for misleading wardens, INFO for minor inaccuracies)

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| NatSpec extraction | Manual parsing | Direct source reading | NatSpec parsers would miss inline comments; manual reading catches all categories |
| Diff comparison | Custom diff tooling | `git diff HEAD -- contracts/modules/` | Working tree vs committed HEAD shows exactly what changed |
| v3.1 finding lookup | Memory/re-discovery | `git show HEAD:audit/v3.1-findings-{32,33}-*.md` | Previous findings are preserved in git even though files were deleted from working tree |

## Common Pitfalls

### Pitfall 1: Auditing HEAD instead of working tree
**What goes wrong:** Reading committed HEAD misses the v3.1 fixes and shows stale code
**Why it happens:** Habit of using `git show` for source
**How to avoid:** Always read from the filesystem directly (`Read` tool), not from git
**Warning signs:** Finding issues that are already in the v3.1 findings list

### Pitfall 2: Assuming v3.1 fixes are correct without verification
**What goes wrong:** A fix for CMT-027 ("50/50" -> "25% each") might itself be wrong
**Why it happens:** Trusting the fix text without independently verifying against code
**How to avoid:** For each fix, read the actual code and verify the new comment matches
**Warning signs:** Fix text that sounds plausible but uses different numbers than the code

### Pitfall 3: Missing cascading comment effects from code changes
**What goes wrong:** Decimator expiry removal changes behavior, but comments elsewhere still reference the old behavior
**Why it happens:** Code change was applied to DecimatorModule but other modules might reference decimator expiry
**How to avoid:** Grep for "expir", "TerminalDecAlreadyClaimed", "round-scoped", "claim window" across all module files
**Warning signs:** Any comment mentioning decimator claims timing or windows

### Pitfall 4: Conflating "9 modules" with actual file count
**What goes wrong:** Skipping GameOverModule, PayoutUtils, or MintStreakUtils because they're not in the count
**Why it happens:** Roadmap says "9 modules" but there are 12 files
**How to avoid:** Audit all 12 files in contracts/modules/
**Warning signs:** Finding unaudited files at the end

### Pitfall 5: Duplicate finding with v3.1
**What goes wrong:** Reporting a finding that was already found and fixed in v3.1
**Why it happens:** Not checking the v3.1 findings list before flagging
**How to avoid:** Cross-reference each finding against v3.1 findings (CMT-011 through CMT-040)
**Warning signs:** Finding text matches a v3.1 entry

## Code Examples

### Reading v3.1 findings from git (since files were deleted from working tree)
```bash
# Batch A findings (MintModule, DegeneretteModule, WhaleModule, BoonModule, LootboxModule, PayoutUtils, MintStreakUtils)
git show HEAD:audit/v3.1-findings-32-game-modules-batch-a.md

# Batch B findings (JackpotModule, DecimatorModule, EndgameModule, GameOverModule, AdvanceModule)
git show HEAD:audit/v3.1-findings-33-game-modules-batch-b.md

# Consolidated (all 84 findings with severity index)
git show HEAD:audit/v3.1-findings-consolidated.md
```

### Checking what changed in working tree
```bash
# Summary of changes per module file
git diff HEAD --stat -- contracts/modules/

# Full diff for a specific file
git diff HEAD -- contracts/modules/DegenerusGameDecimatorModule.sol

# Search for stale references across all modules
grep -rn "expir\|TerminalDecAlreadyClaimed\|rngLocked" contracts/modules/
```

### Finding format example (from v3.1)
```markdown
### CMT-027: _processAutoRebuy NatSpec says "next level or next+1 (50/50)" but code uses 1-4 levels (25% each)

- **What:** The `@dev` NatSpec for `_processAutoRebuy` at line 980 states `Converts winnings to tickets for next level or next+1 (50/50)`. The actual implementation uses `levelOffset = (entropy & 3) + 1`, producing values 1-4 with 25% each.
- **Where:** DegenerusGameJackpotModule.sol:980
- **Why:** A warden modeling auto-rebuy fund flow would assume a 50/50 split between two levels, underestimating the 4-level spread and 75% futurePrizePool routing.
- **Suggestion:** Change to: `Converts winnings to tickets 1-4 levels ahead (25% each; +1 goes to nextPrizePool, +2/+3/+4 go to futurePrizePool).`
- **Category:** comment-inaccuracy
- **Severity:** INFO
```

## State of the Art

| Old Approach (v3.1) | Current Approach (v3.2) | What Changed |
|---------------------|------------------------|--------------|
| Flag-only, no code changes | Fresh re-scan of post-fix code | v3.1 fixes now applied in working tree; code changes (decimator expiry) also applied |
| 2 batches (Phases 32-33, 7+5 files) | Single phase (all 12 files) | Unified scan is more efficient since all fixes are already applied |
| CMT-011 through CMT-040 numbering | Fresh numbering (CMT-V32-NNN) | Avoids confusion with v3.1 findings that are now fixed |

## Open Questions

1. **Should the findings file track v3.1 fix verification separately?**
   - What we know: v3.1 found 31 issues in module files, all fixed in working tree
   - What's unclear: Whether the deliverable should have a "v3.1 fix verification" section or just report new findings
   - Recommendation: Include a brief "v3.1 Fixes Verified" summary table (pass/fail per finding) followed by new findings. This proves the fixes were independently verified.

2. **GameOverModule DRIFT-003 -- was it fixed?**
   - What we know: GameOverModule has no uncommitted changes, but v3.1 found DRIFT-003 (_sendToVault hard-revert risk absent from NatSpec)
   - What's unclear: Whether this was intentionally left unfixed or overlooked
   - Recommendation: Note it in the findings if still present in working tree

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Hardhat (JS) + Foundry (Solidity fuzz) |
| Config file | hardhat.config.js, foundry.toml |
| Quick run command | `npx hardhat test test/unit/DegenerusGame.test.js` |
| Full suite command | `npx hardhat test` |

### Phase Requirements -> Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| CMT-01 | Comment correctness across module files | manual-only | N/A -- comment audit is inherently manual review | N/A |

**Justification for manual-only:** Comment correctness cannot be automated. NatSpec accuracy requires human judgment about whether a comment matches code behavior. No test framework can validate "does this @dev accurately describe the function?"

### Sampling Rate
- **Per task commit:** N/A -- no code changes, findings file only
- **Per wave merge:** N/A
- **Phase gate:** Findings file exists and follows established format

### Wave 0 Gaps
None -- no test infrastructure needed for manual review.

## Sources

### Primary (HIGH confidence)
- Direct file system reading of contracts/modules/*.sol (working tree)
- `git diff HEAD -- contracts/modules/` (actual uncommitted changes)
- `git show HEAD:audit/v3.1-findings-consolidated.md` (v3.1 findings reference)
- `git show HEAD:audit/v3.1-findings-32-game-modules-batch-a.md` (Batch A details)
- `git show HEAD:audit/v3.1-findings-33-game-modules-batch-b.md` (Batch B details)
- contracts/ContractAddresses.sol (10 module addresses)
- .planning/REQUIREMENTS.md (CMT-01 requirement definition)
- .planning/ROADMAP.md (Phase 39 scope and success criteria)

### Secondary (MEDIUM confidence)
- v3.1 Phase 32 research from git (methodology and pre-identified issues)

### Tertiary (LOW confidence)
- None

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH -- no libraries, just source files and git
- Architecture: HIGH -- file inventory verified by direct listing, change analysis from git diff
- Pitfalls: HIGH -- based on actual v3.1 experience with same codebase

**Research date:** 2026-03-19
**Valid until:** 2026-04-02 (14 days -- stable unless new code changes land)
