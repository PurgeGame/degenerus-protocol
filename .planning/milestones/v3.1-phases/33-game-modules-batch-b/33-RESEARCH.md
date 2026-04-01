# Phase 33: Game Modules Batch B - Research

**Researched:** 2026-03-18
**Domain:** Solidity NatSpec/inline comment verification + intent drift detection for 5 game module contracts
**Confidence:** HIGH

## Summary

Phase 33 audits the NatSpec and inline comments of 5 game module contracts totaling 5,977 lines: DegenerusGameJackpotModule.sol (2,795 lines), DegenerusGameDecimatorModule.sol (1,027 lines), DegenerusGameEndgameModule.sol (540 lines), DegenerusGameGameOverModule.sol (232 lines), and DegenerusGameAdvanceModule.sol (1,383 lines). The deliverable is a per-batch findings file listing every comment inaccuracy and intent drift item, each with what/why/suggestion. No code changes are made.

Three of the 5 contracts were modified after Phase 29: JackpotModule received 2 commits (a2093fd6 tightening x00 future pool keep-roll range to 30-65%, and 4cefca59 removing the rare 1-in-1e15 future pool dump on non-x00 levels). DecimatorModule received 1 commit (30e193ff blocking burns when <= 1 day remains on death clock and shifting the time multiplier curve back 1 day). GameOverModule received 1 commit (df1e9f78 simplifying the level-0 guard in handleGameOverDrain). The other 2 contracts (EndgameModule and AdvanceModule) have NOT been modified since Phase 29.

The JackpotModule NatSpec for `consolidatePrizePools` and `_futureKeepBps` was updated by both post-Phase-29 commits -- the stale "0-100% keep (avg 50%)" was corrected to "30-65% keep (avg ~47.5%)" and the "1-in-1e15 chance to dump 90%" flow reference was removed. The DecimatorModule NatSpec for `recordTerminalDecBurn` and `_terminalDecMultiplierBps` was updated by 30e193ff. However, the GameOverModule level-0 simplification (df1e9f78) may have left surrounding NatSpec stale. All updates need independent verification.

**Primary recommendation:** Split work into 3 plans. JackpotModule (2,795 lines, 147 NatSpec tags, 56 functions) is the largest module and gets its own plan. DecimatorModule (1,027 lines, 161 NatSpec tags, 30 functions -- highest NatSpec density) also gets its own plan. The remaining 3 smaller contracts (EndgameModule 540 lines, GameOverModule 232 lines, AdvanceModule 1,383 lines) share the third plan, which also handles findings file finalization. AdvanceModule has 71 NatSpec tags and 37 functions but most are short helper wrappers around delegatecall dispatches -- its review complexity is lower than its line count suggests.

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| CMT-03 | All NatSpec and inline comments in game modules batch B (JackpotModule, DecimatorModule, EndgameModule, GameOverModule, AdvanceModule) are accurate and warden-ready | 5,977 total lines across 5 contracts. 423 NatSpec tags total, ~1,165 comment lines, 137 functions. 3 contracts modified post-Phase-29 (JackpotModule 2 commits, DecimatorModule 1 commit, GameOverModule 1 commit). Post-Phase-29 NatSpec updates need independent verification. All contracts are delegatecall modules operating on DegenerusGameStorage. |
| DRIFT-03 | Game modules batch B reviewed for vestigial logic, unnecessary restrictions, and intent drift | Key areas to check: (1) JackpotModule removal of FUTURE_DUMP_TAG/FUTURE_DUMP_ODDS and _shouldFutureDump -- any vestigial references in comments or dead code paths, (2) DecimatorModule shifted burn deadline from day 0 to day 1 -- any inconsistent references to the old "remaining=0" rule, (3) GameOverModule simplified level-0 guard -- any NatSpec still describing the old `level == 0 ? 1 : level` logic, (4) AdvanceModule cross-module delegatecall NatSpec accuracy (this module orchestrates all others), (5) EndgameModule BAF/Decimator schedule descriptions matching actual trigger logic. |
</phase_requirements>

## Standard Stack

This phase does not introduce any libraries or tools. It is a purely manual audit task using existing project infrastructure.

### Core
| Tool | Purpose | Why Standard |
|------|---------|--------------|
| Solidity source files | Primary verification target | contracts/modules/ directory is source of truth (per project memory: NEVER read from degenerus-contracts/ or testing/contracts/) |
| Phase 31 findings file | Pattern reference for findings format | audit/v3.1-findings-31-core-game-contracts.md establishes CMT/DRIFT numbering, severity conventions, and format |
| Phase 32 findings file | Numbering continuation reference | audit/v3.1-findings-32-game-modules-batch-a.md ended at CMT-024 and DRIFT-002 (0 drift in batch A) |
| Git history | Identify post-Phase-29 changes | Commits a2093fd6, 4cefca59 (JackpotModule), 30e193ff (DecimatorModule), df1e9f78 (GameOverModule) changed contracts after Phase 29 |

### Ground Truth Sources (for cross-reference)
| Source | Location | What It Proves |
|--------|----------|---------------|
| Phase 31 findings | audit/v3.1-findings-31-core-game-contracts.md | Established format: CMT-NNN / DRIFT-NNN numbering with what/where/why/suggestion/category/severity fields. Phase 31 ended at CMT-010, DRIFT-002. |
| Phase 32 findings | audit/v3.1-findings-32-game-modules-batch-a.md | Phase 32 ended at CMT-024, DRIFT-002 (0 new drift findings). 14 CMT total across 7 contracts. Phase 33 continues at CMT-025, DRIFT-003. |
| Phase 29 verification | .planning/phases/29-comment-documentation-correctness/29-VERIFICATION.md | What Phase 29 already verified |
| Phase 29 Plan 03 summary | .planning/phases/29-comment-documentation-correctness/29-03-SUMMARY.md | Module NatSpec Part 2 -- 24 verdicts across 8 modules including EndgameModule, GameOverModule. GO-05-F01 _sendToVault revert risk flagged as absent from NatSpec. |
| KNOWN-ISSUES.md | audit/KNOWN-ISSUES.md | Design decisions documented for wardens |
| PAYOUT-SPECIFICATION.html | audit/PAYOUT-SPECIFICATION.html | Comprehensive payout flow reference |

## Architecture Patterns

### Contract File Inventory (by size, for work ordering)

```
contracts/modules/DegenerusGameJackpotModule.sol       2,795 lines  (147 NatSpec tags, ~453 comment lines, 56 functions) [POST-PHASE-29 CHANGES x2]
contracts/modules/DegenerusGameAdvanceModule.sol       1,383 lines  (71 NatSpec tags, ~234 comment lines, 37 functions)
contracts/modules/DegenerusGameDecimatorModule.sol     1,027 lines  (161 NatSpec tags, ~287 comment lines, 30 functions) [POST-PHASE-29 CHANGES x1]
contracts/modules/DegenerusGameEndgameModule.sol         540 lines  (23 NatSpec tags, ~134 comment lines, 7 functions)
contracts/modules/DegenerusGameGameOverModule.sol        232 lines  (21 NatSpec tags, ~57 comment lines, 7 functions) [POST-PHASE-29 CHANGES x1]
                                                       -----
Total:                                                 5,977 lines  (423 NatSpec tags, ~1,165 comment lines, 137 functions)
```

### Module Inheritance/Dependency Structure

```
DegenerusGameStorage (abstract)
  |
  +-- DegenerusGamePayoutUtils (abstract)
  |     |
  |     +-- DegenerusGameJackpotModule (concrete, standalone)
  |     |
  |     +-- DegenerusGameDecimatorModule (concrete, standalone)
  |     |
  |     +-- DegenerusGameEndgameModule (concrete, standalone)
  |
  +-- DegenerusGameGameOverModule (concrete, standalone -- inherits Storage directly, NOT PayoutUtils)
  |
  +-- DegenerusGameAdvanceModule (concrete, standalone -- inherits Storage directly, NOT PayoutUtils)
```

Key implications for NatSpec review:
- JackpotModule, DecimatorModule, and EndgameModule inherit PayoutUtils helpers (_creditClaimable, _calcAutoRebuy, _queueWhalePassClaimCore)
- GameOverModule and AdvanceModule inherit Storage directly -- they cannot use PayoutUtils helpers
- AdvanceModule is the orchestrator: it delegatecalls into JackpotModule, EndgameModule, and GameOverModule
- AdvanceModule also delegatecalls into MintModule (already audited in Phase 32) for ticket processing
- All modules operate on DegenerusGameStorage via delegatecall from DegenerusGame

### Post-Phase-29 Code Changes (Critical Context)

| Contract | Commit | Changes | Impact on Comments |
|----------|--------|---------|--------------------|
| JackpotModule | a2093fd6 | Tightened x00 future pool keep-roll range from 0-100% (avg 50%) to 30-65% (avg ~47.5%). Changed `_futureKeepBps` formula from `(total * 10_000) / 15` to `3000 + (total * 3500) / 15`. | NatSpec on `consolidatePrizePools` (line 871) UPDATED: now says "30-65%, avg ~47.5%". NatSpec on `_futureKeepBps` (line 1281) UPDATED: now says "30-65% keep (avg ~47.5%)". Need to verify no other comments reference the old range. |
| JackpotModule | 4cefca59 | Removed rare future pool dump on non-x00 levels: deleted `FUTURE_DUMP_TAG`, `FUTURE_DUMP_ODDS` constants, `_shouldFutureDump` function, and the else-if branch in `consolidatePrizePools` that called it. | NatSpec on `consolidatePrizePools` UPDATED: removed "On other levels: 1-in-1e15 chance to dump 90% of future into current." Need to verify no cross-references to removed feature remain in comments elsewhere (DegenerusGame.sol jackpot headers already flagged stale in Phase 31 CMT-006/007/008). |
| DecimatorModule | 30e193ff | Changed burn block condition from `daysRemaining == 0` to `daysRemaining <= 1` (24h cooldown before termination). Shifted time multiplier curve: `_terminalDecMultiplierBps` formula changed from `10000 + ((daysRemaining - 1) * 10000) / 9` to `10000 + ((daysRemaining - 2) * 10000) / 8`. | NatSpec on `recordTerminalDecBurn` (line 800) UPDATED: now says "Burns blocked when <= 1 day remains (24h cooldown before termination)." NatSpec on `_terminalDecMultiplierBps` (line 997-998) UPDATED: now says "linear 2x (day 10) to 1x (day 2), burns blocked at day 1." Inline comment (line 1004) UPDATED: now says "Linear: 2x at day 10, 1x at day 2 (day 1 blocked by caller)." |
| GameOverModule | df1e9f78 | Simplified level-0 guard: removed `uint24 currentLevel = level; uint24 lvl = currentLevel == 0 ? 1 : currentLevel;` and replaced with plain `uint24 lvl = level;`. Changed early game-over check from `if (currentLevel < 10)` to `if (lvl < 10)`. | No NatSpec described the level-0 guard specifically, so no stale NatSpec from this change. However, the overall function NatSpec should be verified for accuracy with the simplified logic. |

AdvanceModule and EndgameModule: NO changes since Phase 29.

### Recommended Plan Split

Based on contract sizes, NatSpec density, and post-Phase-29 change concentration:

**Plan 1 (Wave 1): JackpotModule (2,795 lines)**
- Largest module with most complex logic (prize pool splits, daily jackpots, ticket processing, auto-rebuy)
- 2 post-Phase-29 commits to verify
- 147 NatSpec tags, 56 functions
- Creates the batch findings file with header

**Plan 2 (Wave 1, parallel): DecimatorModule (1,027 lines)**
- Highest NatSpec density (161 tags in 1,027 lines -- more tags than JackpotModule despite being 1/3 the size)
- 1 post-Phase-29 commit to verify
- Complex terminal decimator mechanics (burn tracking, bucket/subbucket, time multiplier curve)
- Can run in parallel with Plan 1

**Plan 3 (Wave 2, depends on Plans 1+2): EndgameModule + GameOverModule + AdvanceModule + Finalize (2,155 lines combined)**
- EndgameModule (540 lines, 23 tags, 7 functions): unchanged, BAF/Decimator dispatch and affiliate rewards
- GameOverModule (232 lines, 21 tags, 7 functions): 1 minor post-Phase-29 change, smallest contract
- AdvanceModule (1,383 lines, 71 tags, 37 functions): unchanged, orchestrator with many delegatecall wrappers
- Finalize: update summary counts, cross-check all 5 contract sections, verify numbering

### Finding Numbering Continuation

Phase 31 ended at: CMT-010, DRIFT-002
Phase 32 ended at: CMT-024, DRIFT-002 (no new DRIFT findings in batch A)
Phase 33 starts at: CMT-025, DRIFT-003

### Findings File Format

```markdown
# Phase 33 Findings: Game Modules Batch B

**Date:** 2026-03-18
**Scope:** JackpotModule, DecimatorModule, EndgameModule, GameOverModule, AdvanceModule
**Pass:** v3.1 second independent review (v3.0 Phase 29 was first pass)
**Mode:** Flag-only -- no code changes

## Summary

| Contract | CMT findings | DRIFT findings | Total |
|----------|-------------|----------------|-------|
| DegenerusGameJackpotModule.sol | X | Y | Z |
| DegenerusGameDecimatorModule.sol | X | Y | Z |
| DegenerusGameEndgameModule.sol | X | Y | Z |
| DegenerusGameGameOverModule.sol | X | Y | Z |
| DegenerusGameAdvanceModule.sol | X | Y | Z |
| **Total** | **X** | **Y** | **Z** |

*Summary counts updated after all contracts reviewed.*

## [Contract] Findings

### CMT-0NN: [Brief title]
- **What:** [The specific comment inaccuracy]
- **Where:** [File:Line]
- **Why:** [Why a warden would be misled]
- **Suggestion:** [Recommended fix]
- **Category:** comment-inaccuracy | intent-drift
- **Severity:** INFO | LOW
```

### Verification Methodology for v3.1

Same methodology as Phases 31-32, adapted for Batch B module contracts:

**CMT-03 approach (comment accuracy):**
1. For each contract, read every NatSpec tag (@notice, @dev, @param, @return, @custom) and every inline // comment
2. For each comment, verify it matches actual code behavior in the current HEAD
3. Focus on warden-readability: "Would a C4A warden reading this be misled?"
4. Flag any mismatch as a finding with what/why/suggestion
5. Pay special attention to post-Phase-29 NatSpec updates in JackpotModule, DecimatorModule, and GameOverModule -- verify completeness
6. Verify AdvanceModule delegatecall dispatch NatSpec matches the module functions it calls

**DRIFT-03 approach (intent drift):**
1. Scan for vestigial references to removed features (future dump odds, old burn deadline, old keep-roll range)
2. Check for guards/conditions that may have become unnecessary after code changes
3. Look for logic whose behavior has changed but whose surrounding commentary still describes old behavior
4. Check for orphaned NatSpec from removed functions (pattern from CMT-010/011/020 in Phases 31-32)
5. Flag any drift as a finding with what/why/suggestion

### Anti-Patterns to Avoid

- **Rubber-stamping Phase 29 verdicts for changed contracts:** JackpotModule, DecimatorModule, and GameOverModule all changed after Phase 29. Do not assume Phase 29 results are still valid for these contracts.
- **Missing cross-module NatSpec staleness:** AdvanceModule contains extensive NatSpec describing what JackpotModule, EndgameModule, and GameOverModule do. These descriptions must match the CURRENT behavior of those modules, not their Phase 29 behavior. The AdvanceModule delegatecall section header (lines 480-492) lists the module purposes.
- **Overlooking the JackpotModule future dump removal impact:** Commit 4cefca59 removed `_shouldFutureDump`, `FUTURE_DUMP_TAG`, and `FUTURE_DUMP_ODDS`. Verify no other comments, section headers, or NatSpec in JackpotModule reference the old 1-in-1e15 dump mechanic.
- **Missing Phase 29 prior findings:** Phase 29 Plan 03 flagged GO-05-F01: `_sendToVault` hard-revert risk absent from GameOverModule NatSpec. Verify whether this was subsequently added or still needs flagging.
- **Ignoring block comments and section headers:** JackpotModule has extensive architecture block comments (lines 16-43) describing jackpot flow, fund accounting, and randomness patterns. These are prime warden reading material.
- **Scope creep into code fixes:** If a real bug or optimization is found, document it as a finding but do NOT attempt code changes. This is flag-only.
- **Scale confusion (BPS vs raw percentages):** JackpotModule uses both BPS (10,000 denominator) and raw percentages (100 denominator) for different calculations. The keep-roll uses BPS (3000-6500), daily jackpot percentages use raw % (6%-14%), and pool splits use raw division (1/10 for decimator). Verify each percentage comment against its actual denominator.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Finding post-Phase-29 changes | Manual git log | `git diff bd910dd0..HEAD -- contracts/modules/DegenerusGameJackpotModule.sol` | Precise diff of what changed after Phase 29 |
| Counting NatSpec tags | Manual counting | `grep -cE '@dev\|@notice\|@param\|@return' contracts/modules/File.sol` | Accurate enumeration |
| Finding orphaned NatSpec | Reading all comments manually | `grep -n '/// @notice\|/// @dev' FILE` then diff with function declarations | Quick identification of detached NatSpec |
| Finding stale future dump references | Reading all comments manually | `grep -in 'future.*dump\|1e15\|quadrillion\|dump.*90%' FILE` | Quick identification of removed feature references |
| Finding stale keep-roll range references | Reading all comments manually | `grep -in '0-100%\|avg 50%\|average 50' FILE` | Quick identification of old range references |
| Verifying BPS/percentage annotations | Mental math | `grep -n 'BPS\|bps\|%' FILE` to list all scale annotations | Catches scale confusion |

## Common Pitfalls

### Pitfall 1: Stale Cross-Module NatSpec in AdvanceModule
**What goes wrong:** AdvanceModule NatSpec describes what other modules do, but those modules changed after Phase 29
**Why it happens:** AdvanceModule is the orchestrator and contains descriptive comments about the behavior of modules it calls via delegatecall. When those modules change, the AdvanceModule descriptions may become stale.
**How to avoid:** For every delegatecall wrapper in AdvanceModule, verify the NatSpec description matches the current behavior of the target module. Key areas: `_consolidatePrizePools` wrapper (lines 531-544), `payDailyJackpot` wrapper (lines 564-585), game over path (lines 410-460).
**Warning signs:** AdvanceModule NatSpec saying "0-100% keep" or "1-in-1e15 dump" when JackpotModule no longer has these features.

### Pitfall 2: Assuming NatSpec Updates in Post-Phase-29 Commits Are Complete
**What goes wrong:** Assuming that the commits that changed JackpotModule and DecimatorModule also updated all relevant NatSpec
**Why it happens:** The commit messages suggest NatSpec was updated, but may have only fixed the most obvious issues
**How to avoid:** Re-verify ALL NatSpec in changed contracts, not just the lines touched by the commits. This was the exact pattern that caught CMT-017 in Phase 32 (WhaleModule NatSpec partially updated by 9aff84b2).
**Warning signs:** Stale NatSpec close to but not on lines touched by recent commits.

### Pitfall 3: Scale Confusion (BPS vs Raw Percentages)
**What goes wrong:** A comment says a percentage using the wrong scale system
**Why it happens:** JackpotModule uses BPS (10,000 denominator) for keep-roll and some constants, but raw percentages (100 denominator) for daily jackpot distribution and pool splits
**How to avoid:** For every percentage in a comment, verify the denominator. Keep-roll: BPS (3000-6500). Daily jackpot: raw % (DAILY_CURRENT_BPS_MIN=600 -> 6%, DAILY_CURRENT_BPS_MAX=1400 -> 14%). Future pool splits: raw /100. Decimator pool splits: raw /10 or /100.
**Warning signs:** Constants named `*_BPS` that are described as raw percentages, or vice versa.

### Pitfall 4: Missing Phase 29 Prior Findings
**What goes wrong:** Phase 29 flagged specific issues that may still be present
**Why it happens:** Phase 29 reports were deleted from the working tree (commit 8c13fedc) but findings were documented in summaries
**How to avoid:** Check Phase 29 Plan 03 summary for prior findings affecting Batch B contracts. Known: GO-05-F01 `_sendToVault` hard-revert risk absent from GameOverModule NatSpec.
**Warning signs:** GameOverModule `_sendToVault` has @custom:reverts E but does not document that this can permanently block the sweep if stETH transfer reverts.

### Pitfall 5: Overlapping Event Declarations Across Modules
**What goes wrong:** Multiple modules declare the same event (e.g., `AutoRebuyProcessed`, `PlayerCredited`) with potentially different NatSpec
**Why it happens:** Modules are independently compiled and may duplicate event declarations for ABI completeness
**How to avoid:** Check that duplicate events have consistent NatSpec across modules. JackpotModule, DecimatorModule, and EndgameModule all declare `AutoRebuyProcessed` or `AutoRebuyExecuted` variants. PayoutUtils declares `PlayerCredited`.
**Warning signs:** Same event name in multiple files with different @param descriptions.

## Code Examples

### Identifying Post-Phase-29 Changes

```bash
# JackpotModule (2 commits: keep-roll tightening, future dump removal)
git diff bd910dd0..HEAD -- contracts/modules/DegenerusGameJackpotModule.sol

# DecimatorModule (1 commit: 24h burn cooldown, curve shift)
git diff bd910dd0..HEAD -- contracts/modules/DegenerusGameDecimatorModule.sol

# GameOverModule (1 commit: level-0 guard simplification)
git diff bd910dd0..HEAD -- contracts/modules/DegenerusGameGameOverModule.sol

# Verify EndgameModule and AdvanceModule have NOT changed
git diff bd910dd0..HEAD -- contracts/modules/DegenerusGameEndgameModule.sol
# (empty = no changes)
git diff bd910dd0..HEAD -- contracts/modules/DegenerusGameAdvanceModule.sol
# (empty = no changes)
```

### Verifying Future Dump Removal Is Clean

```bash
# Confirm no references to removed future dump feature remain
grep -in 'future.*dump\|FUTURE_DUMP\|shouldFutureDump\|1e15\|quadrillion' \
  contracts/modules/DegenerusGameJackpotModule.sol
# (should return empty)
```

### Checking Cross-Module Delegatecall Descriptions

```bash
# AdvanceModule delegatecall section header and module list
grep -n 'delegatecall\|GAME_JACKPOT\|GAME_DECIMATOR\|GAME_ENDGAME\|GAME_GAMEOVER' \
  contracts/modules/DegenerusGameAdvanceModule.sol
```

### Verifying Keep-Roll Math

```bash
# _futureKeepBps: total ranges 0-15 (5 dice, 0-3 each)
# Formula: 3000 + (total * 3500) / 15
# Min: 3000 + (0 * 3500) / 15 = 3000 (30%)
# Max: 3000 + (15 * 3500) / 15 = 3000 + 3500 = 6500 (65%)
# Avg: total avg = 5 * 1.5 = 7.5 -> 3000 + (7.5 * 3500) / 15 = 3000 + 1750 = 4750 (47.5%)
# NatSpec says "30-65% keep (avg ~47.5%)" -- CORRECT
```

### Verifying Terminal Dec Multiplier Math

```bash
# _terminalDecMultiplierBps(daysRemaining):
#   > 10: daysRemaining * 2500 (120 days = 300,000 bps = 30x; 11 days = 27,500 bps = 2.75x)
#   <= 10: 10000 + ((daysRemaining - 2) * 10000) / 8
#   Day 10: 10000 + (8 * 10000) / 8 = 10000 + 10000 = 20000 (2x)
#   Day 2: 10000 + (0 * 10000) / 8 = 10000 (1x)
#   Day 1: blocked by caller (daysRemaining <= 1 reverts)
# NatSpec says "2x (day 10) to 1x (day 2), burns blocked at day 1" -- CORRECT
```

## State of the Art

This section is not applicable to a documentation verification phase. No libraries, frameworks, or evolving standards are involved. The Solidity 0.8.34 compiler and NatSpec specification are stable.

## Open Questions

1. **GO-05-F01 _sendToVault NatSpec status**
   - What we know: Phase 29 Plan 03 flagged that `_sendToVault` hard-revert risk is absent from GameOverModule NatSpec. The `@custom:reverts E` tag exists (line 67, line 169, line 193) but does not specifically warn about the permanent game-blocking risk if stETH transfer reverts during the gameover drain.
   - What's unclear: Was this addressed after Phase 29, or does the NatSpec still lack the warning?
   - Recommendation: During the GameOverModule review, specifically check whether `_sendToVault` NatSpec warns about the hard-revert risk. If not, flag as a finding.

2. **AdvanceModule delegatecall wrapper NatSpec depth**
   - What we know: AdvanceModule has many private functions that are thin wrappers around delegatecall to JackpotModule (e.g., `_consolidatePrizePools`, `payDailyJackpot`, `payDailyJackpotCoinAndTickets`, `_payDailyCoinJackpot`). Some have NatSpec, some do not.
   - What's unclear: How deep should the NatSpec review go for internal delegatecall wrappers? Missing NatSpec on private wrappers is less critical than on external functions.
   - Recommendation: Focus on external/public function NatSpec and the delegatecall section header block comment (lines 480-492). Flag missing NatSpec on wrappers only if the wrapper adds behavior beyond pure dispatch.

3. **JackpotModule complexity vs review time**
   - What we know: JackpotModule is 2,795 lines with 147 NatSpec tags, 56 functions, and complex prize pool arithmetic.
   - What's unclear: Whether one plan is sufficient for thorough review, or if it should be split further.
   - Recommendation: Keep JackpotModule as one plan with two tasks. Task 1: contract header, constants, events, and prize pool consolidation/daily jackpot functions. Task 2: ticket processing, auto-rebuy, helper functions, and section review.

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
| CMT-03 | NatSpec and inline comments in 5 game module contracts are accurate and warden-ready | manual-only | N/A -- requires reading and cross-referencing each comment against code | N/A |
| DRIFT-03 | Game modules batch B reviewed for vestigial logic, unnecessary restrictions, and intent drift | manual-only | N/A -- requires understanding designer intent vs actual behavior | N/A |

**Justification for manual-only:** This phase verifies the semantic accuracy of human-written English comments against code behavior and design intent. There is no automated tool that can determine whether a NatSpec description would mislead a C4A warden. The verification requires understanding the delegatecall execution context, cross-module interactions, post-Phase-29 code changes, and the protocol's intended design.

### Sampling Rate
- **Per task commit:** Review findings file for completeness -- every function and block comment in the target contract(s) should be covered
- **Per wave merge:** Cross-check that all 5 contracts are covered with no files missed
- **Phase gate:** CMT-03 and DRIFT-03 both have explicit verdicts; a per-batch findings file exists with what/why/suggestion for every item

### Wave 0 Gaps
None -- no test infrastructure needed. This is a documentation/findings-only audit phase producing a findings markdown file.

## Sources

### Primary (HIGH confidence)
- contracts/modules/DegenerusGameJackpotModule.sol -- 2,795 lines, key sections read during research (header, consolidatePrizePools, _futureKeepBps, dice roll section)
- contracts/modules/DegenerusGameDecimatorModule.sol -- 1,027 lines, key sections read during research (recordTerminalDecBurn, _terminalDecMultiplierBps, header)
- contracts/modules/DegenerusGameEndgameModule.sol -- 540 lines, read in full during research
- contracts/modules/DegenerusGameGameOverModule.sol -- 232 lines, read in full during research
- contracts/modules/DegenerusGameAdvanceModule.sol -- 1,383 lines, key sections read during research (advanceGame, rngGate, delegatecall wrappers, VRF functions)
- git diff bd910dd0..HEAD -- verified 3 contracts changed, 2 unchanged since Phase 29
- git log bd910dd0..HEAD -- identified 4 specific commits affecting Batch B contracts
- audit/v3.1-findings-31-core-game-contracts.md -- Phase 31 findings format and numbering reference (CMT-001 through CMT-010, DRIFT-001 through DRIFT-002)
- audit/v3.1-findings-32-game-modules-batch-a.md -- Phase 32 findings continuation (CMT-011 through CMT-024, 0 new DRIFT)
- .planning/phases/31-core-game-contracts/31-RESEARCH.md -- Phase 31 research methodology reference
- .planning/phases/32-game-modules-batch-a/32-RESEARCH.md -- Phase 32 research methodology reference
- .planning/phases/29-comment-documentation-correctness/29-03-SUMMARY.md -- Phase 29 module NatSpec results

### Secondary (MEDIUM confidence)
- Phase 29 detailed audit reports recoverable via git show bd910dd0:audit/v3.0-doc-*.md -- deleted but in history
- .planning/PROJECT.md -- Key decisions table

## Metadata

**Confidence breakdown:**
- Scope assessment: HIGH -- all 5 contract files partially read, line/NatSpec/function counts verified via grep, post-Phase-29 changes identified via git diff with exact commits
- Post-Phase-29 change analysis: HIGH -- all 4 commits reviewed, diffs read in full, NatSpec updates verified against code changes
- Methodology: HIGH -- standard NatSpec/inline review approach proven in Phases 31-32, reusing established findings format
- Plan structure: HIGH -- contract sizes and NatSpec density analysis support the 3-plan split with parallel Wave 1
- Completeness of pre-identified issues: MEDIUM -- post-Phase-29 NatSpec updates appear to have been done correctly (unlike Phase 32's WhaleModule where updates were incomplete), but full review may find additional issues in the ~423 NatSpec tags and ~1,165 comment lines

**Research date:** 2026-03-18
**Valid until:** 2026-04-17 (30 days -- stable domain, contracts not expected to change during audit prep)
