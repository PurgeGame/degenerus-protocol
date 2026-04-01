# Phase 31: Core Game Contracts - Research

**Researched:** 2026-03-18
**Domain:** Solidity NatSpec/inline comment verification + intent drift detection for DegenerusGame.sol, DegenerusGameStorage.sol, DegenerusAdmin.sol
**Confidence:** HIGH

## Summary

Phase 31 is the first phase of v3.1 and performs a second independent pass over the three core game contracts: DegenerusGame.sol (2,856 lines), DegenerusGameStorage.sol (1,631 lines), and DegenerusAdmin.sol (801 lines) -- totaling 5,288 lines. The deliverable is a per-batch findings file listing every comment inaccuracy and intent drift item, each with what/why/suggestion. No code changes are made.

v3.0 Phase 29 already performed a first pass: 108 functions verified in DegenerusGame.sol (105 MATCH, 1 DISCREPANCY), 20 functions verified in DegenerusAdmin.sol (20 MATCH, 0 DISCREPANCY), and storage layout byte-verified across 3 EVM slots. However, Phase 29's audit reports were subsequently deleted during repo cleanup (commit 8c13fedc), and critically, DegenerusAdmin.sol received two code-changing commits AFTER Phase 29 completed (df1e9f78 adding 1-per-address proposal limit + voidedUpTo watermark, and fd9dbad1 lowering initial threshold from 60% to 50%). These post-Phase-29 changes introduced at least two demonstrably stale header comments in DegenerusAdmin.sol that were NOT present when Phase 29 ran. DegenerusGame.sol and DegenerusGameStorage.sol have NOT been modified since Phase 29.

The v3.1 pass has a different focus than v3.0 Phase 29: warden-readability and intent drift. Phase 29 was a correctness cross-reference against audit verdicts. Phase 31 reads the contracts with fresh eyes, asking "Would a C4A warden reading this comment be misled?" and "Does this logic still match what the designer intended?"

**Primary recommendation:** Split work by contract. DegenerusAdmin.sol is smallest (801 lines) but has the most post-Phase-29 changes and known stale comments -- start there. DegenerusGameStorage.sol (1,631 lines) is the storage layout with verified byte offsets but extensive inline documentation to re-read for warden clarity. DegenerusGame.sol (2,856 lines) is the largest and needs the most careful function-by-function NatSpec and inline review.

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| CMT-01 | All NatSpec and inline comments in core game contracts (DegenerusGame, GameStorage, DegenerusAdmin) are accurate and warden-ready | 5,288 total lines across 3 contracts. 57 NatSpec tags in DegenerusAdmin, 507 in DegenerusGame, 218 in DegenerusGameStorage. ~1,448 total comment lines (140 in Admin, 664 in Game, 644 in Storage). Phase 29 did first pass; v3.1 is second pass focusing on warden-readability. At least 2 known stale comments in DegenerusAdmin from post-Phase-29 code changes. |
| DRIFT-01 | Core game contracts reviewed for vestigial logic, unnecessary restrictions, and intent drift | Three categories to check: (1) vestigial guards from removed features (death clock pause, activeProposalCount), (2) unnecessary restrictions that may have accumulated through iterative hardening, (3) logic whose behavior drifted from what comments/docs describe (e.g., threshold decay starting at 50% but header says 60%). Post-Phase-29 changes to DegenerusAdmin.sol are prime intent-drift candidates. |
</phase_requirements>

## Standard Stack

This phase does not introduce any libraries or tools. It is a purely manual audit task using existing project infrastructure.

### Core
| Tool | Purpose | Why Standard |
|------|---------|--------------|
| Solidity source files | Primary verification target | contracts/ directory is source of truth (per project memory: NEVER read from degenerus-contracts/ or testing/contracts/) |
| Prior audit reports | Ground truth for verified behavior | Phases 26-28 establish what each function actually does; Phase 29 summaries document what was already checked |
| Git history | Identify post-Phase-29 changes | Commits df1e9f78 and fd9dbad1 changed DegenerusAdmin.sol after Phase 29 |

### Ground Truth Sources (for cross-reference)
| Source | Location | What It Proves |
|--------|----------|---------------|
| Phase 29 summaries | .planning/phases/29-comment-documentation-correctness/29-0X-SUMMARY.md | What Phase 29 already verified and found |
| Phase 29 verification | .planning/phases/29-comment-documentation-correctness/29-VERIFICATION.md | 5/5 DOC requirements satisfied with evidence |
| FINAL-FINDINGS-REPORT.md | audit/FINAL-FINDINGS-REPORT.md | No open findings; overall sound |
| KNOWN-ISSUES.md | audit/KNOWN-ISSUES.md | Design decisions documented for wardens |
| PAYOUT-SPECIFICATION.html | audit/PAYOUT-SPECIFICATION.html | Comprehensive payout flow reference |
| Phase 29 audit docs (deleted) | Recoverable via `git show bd910dd0:audit/v3.0-doc-*.md` | Detailed per-function verdicts from first pass |

## Architecture Patterns

### Contract File Inventory (by size, for work ordering)

```
contracts/DegenerusGame.sol                    2,856 lines  (507 NatSpec tags, ~664 comment lines, 68 ext/pub functions)
contracts/storage/DegenerusGameStorage.sol     1,631 lines  (218 NatSpec tags, ~644 comment lines, storage layout diagram)
contracts/DegenerusAdmin.sol                     801 lines  (57 NatSpec tags, ~140 comment lines, 20 ext/pub functions)
                                               -----
Total:                                         5,288 lines  (782 NatSpec tags, ~1,448 comment lines)
```

### Post-Phase-29 Code Changes (Critical Context)

Only DegenerusAdmin.sol was modified after Phase 29 completed:

| Commit | Date | Changes | Impact on Comments |
|--------|------|---------|--------------------|
| df1e9f78 | 2026-03-18 | Added AlreadyHasActiveProposal error, activeProposalId mapping, voidedUpTo watermark, 1-per-address proposal guard in propose(), updated _voidAllActive | NEW: NatSpec added for activeProposalId (line 274) and voidedUpTo (line 277-278). STALE: None of the header comments were updated. |
| fd9dbad1 | 2026-03-18 | Changed threshold decay from 60%->5% to 50%->5% (removed 24h/6000 tier, return 5000 instead of 6000) | STALE: Header line 38 still says "60% -> 5%". Also updated @return example from 6000=60% to 5000=50%. |

DegenerusGame.sol and DegenerusGameStorage.sol: NO changes since Phase 29.

### Known Stale Comments (Pre-Identified)

These are confirmed stale as of current HEAD and MUST appear in the findings:

| Contract | Line | Issue | Root Cause |
|----------|------|-------|------------|
| DegenerusAdmin.sol | 38 | `Approval voting with decaying threshold (60% -> 5% over 7 days)` -- should be 50% -> 5% | Commit fd9dbad1 changed starting threshold but did not update header |
| DegenerusAdmin.sol | 41 | `Death clock pauses while any proposal is active` -- death clock pause was removed entirely | Commit 73c50cb3 removed death clock pause; header never updated |
| DegenerusGame.sol | 287 | `RNG must be ready (not locked) or recently stale (18h timeout)` -- actual timeout is 12h | VRF retry timeout changed from 18h to 12h (per KEY DECISIONS in PROJECT.md); inline comment never updated |

### Verification Methodology for v3.1

**CMT-01 approach (comment accuracy):**
1. For each contract, read every NatSpec tag (@notice, @dev, @param, @return, @custom) and every inline // comment
2. For each comment, verify it matches actual code behavior in the current HEAD
3. Focus on warden-readability: "Would a C4A warden reading this be misled?"
4. Flag any mismatch as a finding with what/why/suggestion

**DRIFT-01 approach (intent drift):**
1. Scan for vestigial references to removed features (death clock pause, activeProposalCount tracking, old threshold values)
2. Check for guards/conditions that may have become unnecessary after code changes
3. Look for logic whose behavior has changed but whose surrounding commentary still describes old behavior
4. Flag any drift as a finding with what/why/suggestion

**Findings file format (per-batch deliverable):**
```markdown
## [CONTRACT-NAME] Findings

### CMT-[NNN]: [Brief title]
- **What:** [The specific comment inaccuracy]
- **Where:** [File:Line]
- **Why:** [Why a warden would be misled, or why it matters]
- **Suggestion:** [Recommended fix text or action]
- **Category:** comment-inaccuracy | intent-drift
- **Severity:** INFO | LOW

### DRIFT-[NNN]: [Brief title]
- **What:** [The specific drift from design intent]
- **Where:** [File:Line(s)]
- **Why:** [Why the current behavior may not match intent]
- **Suggestion:** [Recommended fix or documentation]
- **Category:** intent-drift
- **Severity:** INFO | LOW
```

### Anti-Patterns to Avoid

- **Rubber-stamping Phase 29 verdicts:** Phase 29 said "20 MATCH, 0 DISCREPANCY" for DegenerusAdmin, but that was BEFORE two code-changing commits. Do not assume Phase 29 results are still valid for DegenerusAdmin. For DegenerusGame.sol and GameStorage.sol (unchanged since Phase 29), Phase 29 results provide useful context but v3.1 should still perform an independent review.
- **Treating this as a re-audit:** This phase verifies COMMENTS and flags DRIFT. Do not re-derive whether functions are correct. The code behavior was proven in Phases 26-28.
- **Missing new NatSpec from post-Phase-29 commits:** The df1e9f78 commit added new NatSpec for activeProposalId and voidedUpTo. These were never reviewed by Phase 29.
- **Only checking NatSpec, ignoring block comments:** DegenerusAdmin.sol lines 6-42 and DegenerusGame.sol lines 4-28 / 85-93 / 279-292 contain extensive block comments describing architecture. These are prime warden reading material and must be checked for staleness.
- **Scope creep into code fixes:** If a real bug or optimization is found, document it as a finding but do NOT attempt code changes. This is flag-only.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Finding post-Phase-29 changes | Manual git log | `git diff bd910dd0..HEAD -- contracts/DegenerusAdmin.sol` | Precise diff of what changed after Phase 29 |
| Recovering Phase 29 detailed reports | Re-doing the analysis | `git show bd910dd0:audit/v3.0-doc-core-game-natspec.md` | Full Phase 29 reports recoverable from git history |
| Counting NatSpec tags | Manual counting | `grep -c '@dev\|@notice\|@param\|@return' contracts/File.sol` | Accurate enumeration |
| Finding stale threshold references | Reading all comments manually | `grep -n '60%\|6000\|death clock\|18h\|912d' contracts/*.sol` | Quick identification of known stale patterns |

## Common Pitfalls

### Pitfall 1: Assuming Phase 29 Results Are Current for DegenerusAdmin
**What goes wrong:** Skipping DegenerusAdmin review because Phase 29 said "0 DISCREPANCY"
**Why it happens:** DegenerusAdmin received 2 code-changing commits after Phase 29 (df1e9f78 and fd9dbad1)
**How to avoid:** Treat DegenerusAdmin as if Phase 29 never reviewed it. The header comment alone has at least 2 demonstrably stale items.
**Warning signs:** Any finding report that says "0 findings in DegenerusAdmin" is almost certainly wrong.

### Pitfall 2: Overlooking Block Comments / Architecture Headers
**What goes wrong:** Only checking per-function NatSpec tags, missing the large block comments at the top of each contract
**Why it happens:** Block comments are not attached to specific functions and may be skipped in a function-by-function review
**How to avoid:** Explicitly review all block comments: DegenerusAdmin.sol lines 6-42, DegenerusGame.sol lines 4-28 / 85-93 / 279-292, DegenerusGameStorage.sol lines 10-116
**Warning signs:** Stale references to "60% threshold" or "death clock pause" in block comments would be missed.

### Pitfall 3: Scale Confusion (BPS vs Half-BPS vs PPM)
**What goes wrong:** A comment says a percentage but the constant uses a different scale
**Why it happens:** The codebase uses BPS (/10000), half-BPS (/20000), and PPM (/1000000)
**How to avoid:** For every percentage in a comment, verify the denominator. DegenerusAdmin uses BPS (10000) exclusively.
**Warning signs:** Half-BPS constants in WhaleModule, PPM in WhaleModule -- but these are NOT in Phase 31 scope.

### Pitfall 4: Confusing "Not Found" with "Correct"
**What goes wrong:** Searching for a known stale pattern, not finding it, and concluding "all clear" when the pattern actually exists with slightly different wording
**Why it happens:** String matching on exact phrases misses paraphrased versions
**How to avoid:** Read the block comments manually, don't rely only on grep
**Warning signs:** grep for "60%" finds it, but grep for "sixty percent" would miss `60%`.

### Pitfall 5: Missing the delegatecall context for DegenerusGame
**What goes wrong:** DegenerusGame.sol comments describe functions as if they execute locally, but many dispatch via delegatecall to modules
**Why it happens:** The delegatecall pattern is well-documented but comment-level descriptions may not clarify execution context
**How to avoid:** For any function that uses delegatecall, verify the NatSpec mentions the module context where relevant
**Warning signs:** NatSpec saying "this contract" when behavior occurs in a module's code.

## Code Examples

### How to Recover Phase 29 Detailed Reports

Phase 29 produced detailed per-function NatSpec verification tables that were deleted in commit 8c13fedc. They are recoverable:

```bash
# Core game NatSpec report (DegenerusGame.sol)
git show bd910dd0:audit/v3.0-doc-core-game-natspec.md

# Peripheral NatSpec report (includes DegenerusAdmin.sol section 6)
git show bd910dd0:audit/v3.0-doc-peripheral-natspec.md

# Storage layout and constants report
git show bd910dd0:audit/v3.0-doc-storage-constants.md
```

These provide useful context for what Phase 29 already checked. For DegenerusGame.sol and GameStorage.sol (unchanged since Phase 29), the Phase 29 verdicts are still valid as a starting point.

### Identifying Post-Phase-29 Changes

```bash
# What changed in DegenerusAdmin after Phase 29 completed
git diff bd910dd0..HEAD -- contracts/DegenerusAdmin.sol

# Verify DegenerusGame.sol has NOT changed
git diff bd910dd0..HEAD -- contracts/DegenerusGame.sol
# (empty = no changes)
```

### Known Stale Comment Patterns to Search For

```bash
# Stale threshold reference
grep -n '60%' contracts/DegenerusAdmin.sol
# Line 38: should be 50%

# Stale death clock reference
grep -n 'death clock\|Death clock' contracts/DegenerusAdmin.sol
# Line 41: death clock pause was removed

# Stale VRF timeout
grep -n '18h\|18 hour' contracts/DegenerusGame.sol
# Line 287: should be 12h
```

### Findings File Template

```markdown
# Phase 31 Findings: Core Game Contracts

**Date:** 2026-03-18
**Scope:** DegenerusGame.sol, DegenerusGameStorage.sol, DegenerusAdmin.sol
**Pass:** v3.1 second independent review (v3.0 Phase 29 was first pass)

## Summary

| Contract | CMT findings | DRIFT findings | Total |
|----------|-------------|----------------|-------|
| DegenerusAdmin.sol | X | Y | Z |
| DegenerusGame.sol | X | Y | Z |
| DegenerusGameStorage.sol | X | Y | Z |
| **Total** | **X** | **Y** | **Z** |

## DegenerusAdmin.sol

### CMT-01: Stale threshold decay description in header
- **What:** ...
- **Where:** DegenerusAdmin.sol:38
- **Why:** ...
- **Suggestion:** ...
- **Category:** comment-inaccuracy
- **Severity:** INFO
```

## State of the Art

This section is not applicable to a documentation verification phase. No libraries, frameworks, or evolving standards are involved. The Solidity 0.8.34 compiler and NatSpec specification are stable.

## Open Questions

1. **Depth of warden-readability review for DegenerusGame.sol**
   - What we know: Phase 29 verified 108 functions and found 1 DISCREPANCY + 3 inline issues. The code has NOT changed since then.
   - What's unclear: How deep should v3.1 go on DegenerusGame.sol given Phase 29 already covered it thoroughly? The risk of finding zero new items is real.
   - Recommendation: Focus the DegenerusGame.sol review on: (1) block comment headers that Phase 29 may have treated as "architecture docs" rather than warden-facing comments, (2) the known stale "18h timeout" comment at line 287, (3) any intent drift in the delegatecall dispatch logic, and (4) any nuances a warden would find confusing even if technically correct.

2. **Severity classification for stale header comments**
   - What we know: DegenerusAdmin.sol header has stale references to "60%" and "death clock pause". These are misleading but do not affect code behavior.
   - What's unclear: Should these be INFO (cosmetic) or LOW (could mislead a warden into filing a finding)?
   - Recommendation: Classify as INFO with a note that a warden reading the header would form incorrect assumptions about governance mechanics. The threshold values in the code itself (line 539) are correct.

3. **Whether to recover and reference Phase 29 reports**
   - What we know: Phase 29 detailed reports are in git history (bd910dd0) but deleted from working tree.
   - What's unclear: Should the v3.1 reviewer read Phase 29 reports as context, or deliberately avoid them for "fresh eyes"?
   - Recommendation: Use Phase 29 reports as reference for efficiency, but do NOT treat Phase 29 "MATCH" verdicts as gospel. Re-verify each comment independently, especially for DegenerusAdmin which changed after Phase 29.

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
| CMT-01 | NatSpec and inline comments in 3 core contracts are accurate and warden-ready | manual-only | N/A -- requires reading and cross-referencing each comment against code | N/A |
| DRIFT-01 | Core game contracts reviewed for vestigial logic, unnecessary restrictions, and intent drift | manual-only | N/A -- requires understanding designer intent vs actual behavior | N/A |

**Justification for manual-only:** This phase verifies the semantic accuracy of human-written English comments against code behavior and design intent. There is no automated tool that can determine whether a NatSpec description would mislead a C4A warden. The verification requires understanding the audit verdicts from Phases 26-28, the post-Phase-29 code changes, and the protocol's intended design.

### Sampling Rate
- **Per task commit:** Review findings file for completeness -- every function and block comment in the target contract(s) should be covered
- **Per wave merge:** Cross-check that all 3 contracts are covered with no files missed
- **Phase gate:** CMT-01 and DRIFT-01 both have explicit verdicts; a per-batch findings file exists with what/why/suggestion for every item

### Wave 0 Gaps
None -- no test infrastructure needed. This is a documentation/findings-only audit phase producing a findings markdown file.

## Sources

### Primary (HIGH confidence)
- contracts/DegenerusGame.sol -- 2,856 lines, read and analyzed
- contracts/storage/DegenerusGameStorage.sol -- 1,631 lines, read and analyzed
- contracts/DegenerusAdmin.sol -- 801 lines, read and analyzed (full file read)
- .planning/phases/29-comment-documentation-correctness/29-VERIFICATION.md -- Phase 29 final verification
- .planning/phases/29-comment-documentation-correctness/29-01-SUMMARY.md -- DegenerusGame.sol Phase 29 results
- .planning/phases/29-comment-documentation-correctness/29-04-SUMMARY.md -- DegenerusAdmin.sol Phase 29 results
- .planning/phases/29-comment-documentation-correctness/29-05-SUMMARY.md -- Storage/Constants Phase 29 results
- git diff df1e9f78^..fd9dbad1 -- contracts/DegenerusAdmin.sol -- exact post-Phase-29 changes verified
- git log --oneline -- contracts/*.sol -- confirmed DegenerusGame.sol and GameStorage.sol unchanged since Phase 29

### Secondary (MEDIUM confidence)
- Phase 29 detailed audit reports recoverable via git show bd910dd0:audit/v3.0-doc-*.md -- deleted but in history
- .planning/PROJECT.md -- Key decisions table documenting threshold change, death clock removal, etc.

## Metadata

**Confidence breakdown:**
- Scope assessment: HIGH -- all 3 contract files read, line/comment counts verified, post-Phase-29 changes identified
- Known stale items: HIGH -- 3 stale comments confirmed by direct code inspection (lines 38, 41 of Admin; line 287 of Game)
- Methodology: HIGH -- standard NatSpec/inline review approach proven in Phase 29, adapted for v3.1 warden-readability focus
- Completeness of pre-identified issues: MEDIUM -- 3 stale items found during research, but full review may find more, especially in DegenerusGame.sol block comments and Storage.sol variable-level NatSpec

**Research date:** 2026-03-18
**Valid until:** 2026-04-17 (30 days -- stable domain, contracts not expected to change during audit prep)
