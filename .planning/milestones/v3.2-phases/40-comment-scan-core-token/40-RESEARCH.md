# Phase 40: Comment Scan -- Core + Token Contracts - Research

**Researched:** 2026-03-19
**Domain:** Solidity NatSpec/inline comment verification -- fresh re-scan after v3.1 fixes applied
**Confidence:** HIGH

## Summary

Phase 40 is a fresh independent comment scan of 7 contracts (3 core game + 4 token) totaling 7,415 lines of Solidity. This is a v3.2 re-scan performed AFTER the protocol team applied fixes from the v3.1 comment audit (84 findings, of which 30 were in these 7 contracts). The goal is to verify that (a) applied fixes are correct and complete, (b) no new comment issues were introduced by the fixes themselves, (c) code changes since v3.1 (rngLocked removal from BurnieCoin shortfall paths, decimator claim expiry removal) have accurate accompanying comments, and (d) any findings missed by the v3.1 scan are caught in this fresh pass.

The contracts split into two natural groups: **Core Game** (DegenerusGame.sol 2,837 lines, DegenerusGameStorage.sol 1,625 lines, DegenerusAdmin.sol 800 lines) and **Token** (BurnieCoin.sol 1,024 lines, DegenerusStonk.sol 226 lines, StakedDegenerusStonk.sol 514 lines, WrappedWrappedXRP.sol 389 lines). Combined they have 1,638 NatSpec lines and 143 external/public functions requiring NatSpec verification.

The working tree shows uncommitted diffs to all 7 contracts -- these are the v3.1 comment fixes. The diffs are the primary focus: verify each fix is correct, verify no partial fixes remain, and verify the rngLocked removal in BurnieCoin is properly documented.

**Primary recommendation:** Split into two plans -- one for core game contracts (DegenerusGame + GameStorage + DegenerusAdmin, ~5,262 lines), one for token contracts (BurnieCoin + DegenerusStonk + StakedDegenerusStonk + WrappedWrappedXRP, ~2,153 lines). Each plan scans its contracts fresh, cross-referencing the v3.1 findings list to verify fixes and catch anything new. Produce per-contract findings grouped in a single findings document.

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| CMT-02 | Core game contracts -- all comments verified (DegenerusGame, GameStorage, DegenerusAdmin) | 5,262 lines, 1,149 NatSpec tags, 73 ext/pub functions. v3.1 found 12 issues (10 CMT + 2 DRIFT). All 12 have corresponding fixes in the working tree diff. Scan must verify fixes and do a fresh independent pass. Prior Phase 29 established methodology; Phase 31 v3.1 findings document provides the fix checklist. |
| CMT-03 | Token contracts -- all comments verified (BurnieCoin, DegenerusStonk, StakedDegenerusStonk, WrappedWrappedXRP) | 2,153 lines, 489 NatSpec tags, 70 ext/pub functions. v3.1 found 18 issues (all CMT). BurnieCoin has the most fixes (13 findings, plus rngLocked removal changes). WrappedWrappedXRP has a known partial fix (line 279 still says "disabled" vs line 19 fixed to "No wrap function"). |
</phase_requirements>

## Standard Stack

This phase does not introduce any libraries or tools. It is a purely manual audit task.

### Core
| Tool | Purpose | Why Standard |
|------|---------|--------------|
| Solidity source files (contracts/) | Primary verification target | Source of truth -- current working tree state |
| v3.1 findings documents (audit/v3.1-findings-*.md) | Fix verification checklist | 30 findings in these 7 contracts to verify |
| v3.0 Phase 29 reports (audit/v3.0-doc-*.md) | Prior NatSpec verdicts as baseline | First-pass verification context |
| Working tree diff (`git diff`) | Shows exactly what changed from v3.1 fixes | Efficient way to verify fix completeness |

### Verification Sources (Ground Truth)
| Source | Content | Use |
|--------|---------|-----|
| audit/v3.1-findings-31-core-game-contracts.md | 12 findings (CMT-001 to CMT-010, DRIFT-001 to DRIFT-002) | Fix checklist for core game contracts |
| audit/v3.1-findings-34-token-contracts.md | 18 findings (CMT-041 to CMT-058) | Fix checklist for token contracts |
| audit/v3.1-findings-consolidated.md | Master summary of all 84 findings | Cross-reference and pattern context |
| Prior Phase 26-28 audit verdicts | Behavioral ground truth | What each function actually does |

## Architecture Patterns

### Contract Inventory for Phase 40

```
Plan 1 -- Core Game Contracts (5,262 lines):
  contracts/DegenerusGame.sol               2,837 lines  (614 /// tags, 51 ext/pub functions)
  contracts/storage/DegenerusGameStorage.sol 1,625 lines  (475 /// tags, 0 ext/pub functions)
  contracts/DegenerusAdmin.sol                800 lines   (60 /// tags, 22 ext/pub functions)

Plan 2 -- Token Contracts (2,153 lines):
  contracts/BurnieCoin.sol                  1,024 lines  (229 /// tags, 29 ext/pub functions)
  contracts/DegenerusStonk.sol                226 lines   (42 /// tags, 12 ext/pub functions)
  contracts/StakedDegenerusStonk.sol          514 lines  (107 /// tags, 18 ext/pub functions)
  contracts/WrappedWrappedXRP.sol              389 lines  (111 /// tags, 11 ext/pub functions)
```

### Verification Methodology

Phase 40 uses a two-pass approach per contract:

**Pass 1: Fix Verification (targeted)**
1. For each v3.1 finding in the contract, check the working tree diff
2. Verify the fix is correct (addresses the finding's "Suggestion")
3. Verify the fix is complete (no partial fixes -- all instances addressed)
4. Flag any fixes that introduced new inaccuracies

**Pass 2: Fresh Independent Scan**
1. Read through the entire file systematically, ignoring what v3.1 found
2. Verify NatSpec on every external/public function (signature, params, returns, reverts)
3. Verify all inline comments describe current code behavior
4. Verify block comment headers match current contract structure
5. Verify storage layout comments (GameStorage) remain accurate
6. Flag any new findings not caught by v3.1

**Output:** Per-contract findings document with:
- Fix verification results (FIXED / PARTIAL / NOT FIXED / NEW ISSUE)
- New findings from fresh scan
- Per-contract summary table

### Anti-Patterns to Avoid
- **Confirming only what v3.1 found:** The fresh scan must be independent. Treat v3.1 findings as a fix checklist, but do the full scan as if it is the first time.
- **Trusting the diff is complete:** The diff shows what changed, but a fix might have missed updating a second instance of the same issue elsewhere in the file. Always verify ALL instances.
- **Skipping "clean" contracts:** Even contracts with 0 v3.1 findings should receive fresh scrutiny. GameStorage had only 2 findings but is 1,625 lines.
- **Ignoring code changes:** The rngLocked removal in BurnieCoin is a real code change, not just a comment fix. Its NatSpec must be verified against the new behavior (BurnieCoinflip now handles RNG lock checks internally).

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Tracking which v3.1 findings were fixed | Manual memory | Cross-reference audit/v3.1-findings-31 and audit/v3.1-findings-34 line by line | 30 findings to verify -- systematic checklist prevents misses |
| Finding all NatSpec tags | Manual scanning | `grep -n '///' contracts/FILE.sol` | Ensures every NatSpec line is checked |
| Verifying fix completeness | Spot-checking | `git diff -- contracts/FILE.sol` shows exact changes | Diff is exhaustive -- every change visible |

## Common Pitfalls

### Pitfall 1: Partial Fixes
**What goes wrong:** A v3.1 finding had a multi-line suggestion (e.g., CMT-057 for WrappedWrappedXRP touched both line 19 and line 278). Only one location was fixed.
**Why it happens:** The protocol team applies fixes manually and may address only the most prominent instance.
**How to avoid:** For each v3.1 finding, check ALL locations mentioned in the finding, not just the primary one. Known example: WrappedWrappedXRP CMT-057 -- line 19 was fixed ("No wrap function") but line 279 still says "Wrapping is disabled."
**Warning signs:** The `git diff` shows a change at one location but no change at a second location referenced in the same finding.

### Pitfall 2: Fix Introduced New Inaccuracy
**What goes wrong:** A fix replaces stale text with new text that is itself inaccurate.
**Why it happens:** Fix was written based on the finding's suggestion without re-verifying against current code.
**How to avoid:** For each fix, verify the NEW text against the current code. Do not assume the v3.1 suggestion was perfectly worded.
**Warning signs:** The diff shows new NatSpec text that uses slightly different terminology than the code.

### Pitfall 3: rngLocked Removal Comment Drift
**What goes wrong:** BurnieCoin removed `if (degenerusGame.rngLocked()) return;` from shortfall paths and added new NatSpec. Any remaining comments elsewhere in BurnieCoin that reference rngLocked behavior in the shortfall context are now stale.
**Why it happens:** The rngLocked check was removed from BurnieCoin but delegated to BurnieCoinflip. Comments in BurnieCoin that referenced the old pattern may not have been updated.
**How to avoid:** Search BurnieCoin for any remaining references to "rngLocked" or "RNG lock" in comments and verify they are accurate with the new architecture.
**Warning signs:** Comments saying BurnieCoin checks rngLocked when it no longer does.

### Pitfall 4: Removed Code Leaving Orphan Comments
**What goes wrong:** DegenerusGame.sol removed the jackpot payout section header (12 lines) and the `futurePrizePoolTotalView` function (5 lines). Surrounding comments may now be out of order or orphaned.
**Why it happens:** When a block is deleted, adjacent comments that referenced it may lose context.
**How to avoid:** After confirming a deletion, read the 5-10 lines above and below the deletion point to verify context continuity.
**Warning signs:** A section header followed by a different section header with no content between them.

### Pitfall 5: DegenerusAdmin Interface Change
**What goes wrong:** `jackpotPhase()` was removed from the `IDegenerusGameAdmin` interface (DRIFT-001 fix). The interface comment at line 67 may still reference "liveness" which was the motivation for jackpotPhase.
**Why it happens:** Interface function removal was done but the interface-level @dev comment was not updated.
**How to avoid:** Verify the interface @dev comment matches the actual interface members.
**Warning signs:** Interface comment mentions capabilities (like "liveness") that no remaining member implements.

## Code Examples

### Fix Verification Pattern

For each v3.1 finding, follow this checklist:

```
Finding: CMT-001 (DegenerusAdmin.sol:38)
  v3.1 said: Header says "60% -> 5%" but code starts at 50%
  Suggestion: Change to "50% -> 5%"

  1. Check git diff: Line 38 changed "60%" to "50%"? YES -> FIX APPLIED
  2. Any other "60%" references in the file? grep -n '60%' -> NONE
  3. New text accurate? threshold() returns 5000 = 50%? YES
  4. Verdict: FIXED CORRECTLY
```

### Fresh Scan Pattern

```
Contract: DegenerusAdmin.sol
Function: propose(address, bytes32) external returns (uint256)

  1. NatSpec at lines 391-398:
     @dev Two paths: Admin (DGVE >50.1%, 20h stall), Community (0.5% sDGNRS, 7d stall)
     @dev Each address may have at most one active proposal at a time. [NEW]
     @param newCoordinator, @param newKeyHash
     @return proposalId

  2. Verify against code:
     - Admin path check: line 400-403 (DGVE balance > totalSupply/2, stall >= 20h) MATCH
     - Community path: line 405-407 (0.5% circulating, stall >= 7d) MATCH
     - 1-per-address limit: line 408 (AlreadyHasActiveProposal) MATCH
     - @param/@return match signature? YES

  3. Verdict: MATCH
```

## v3.1 Findings Fix Status (Pre-Scan Reference)

### Core Game Contracts (12 findings)

| ID | Contract | Fix in Diff? | Notes |
|----|----------|-------------|-------|
| CMT-001 | DegenerusAdmin.sol | YES | 60% -> 50% in header |
| CMT-002 | DegenerusAdmin.sol | YES | Death clock line removed |
| DRIFT-001 | DegenerusAdmin.sol | YES | jackpotPhase() removed from interface |
| DRIFT-002 | DegenerusAdmin.sol | YES | 1-per-address limit added to propose() NatSpec |
| CMT-003 | DegenerusGameStorage.sol | NO | Misplaced SLOT 1 header -- NOT in diff, likely deferred |
| CMT-004 | DegenerusGameStorage.sol | YES | Free-floating NatSpec removed (4 lines deleted) |
| CMT-005 | DegenerusGame.sol | YES | 18h -> 12h in block comment |
| CMT-006 | DegenerusGame.sol | YES* | Entire jackpot payout block deleted (12 lines removed) |
| CMT-007 | DegenerusGame.sol | YES* | Same block -- deleted rather than corrected |
| CMT-008 | DegenerusGame.sol | YES* | Same block -- deleted rather than corrected |
| CMT-009 | DegenerusGame.sol | YES | futurePrizePoolTotalView function removed entirely |
| CMT-010 | DegenerusGame.sol | YES | Orphaned NatSpec line deleted |

*CMT-006/007/008 were fixed by deleting the entire inaccurate jackpot section header block rather than correcting each line. This is a valid fix approach -- verify no replacement was needed.

### Token Contracts (18 findings)

| ID | Contract | Fix in Diff? | Notes |
|----|----------|-------------|-------|
| CMT-041 | BurnieCoin.sol | YES | DATA TYPES section removed (15 lines) |
| CMT-042 | BurnieCoin.sol | YES | BOUNTY STATE section removed (30 lines) |
| CMT-043 | BurnieCoin.sol | YES | "reuses OnlyGame()" inline comment added |
| CMT-044 | BurnieCoin.sol | YES | @dev changed to "game or affiliate (onlyTrustedContracts)" |
| CMT-045 | BurnieCoin.sol | YES | Events header simplified, coinflip/bounty references removed |
| CMT-046 | BurnieCoin.sol | YES | processCoinflipPayouts removed from modifier "Used for" |
| CMT-047 | BurnieCoin.sol | YES | creditCoin added to onlyFlipCreditors "Used for" list |
| CMT-048 | BurnieCoin.sol | YES | onlyTrustedContracts added to security header |
| CMT-049 | BurnieCoin.sol | YES | Section renamed "DECIMATOR & QUEST INTEGRATION HELPERS" |
| CMT-050 | BurnieCoin.sol | YES | vaultEscrow @dev changed to "game contract or vault" |
| CMT-051 | BurnieCoin.sol | YES | _burn @dev references updated (depositCoinflip -> burnCoin) |
| CMT-052 | BurnieCoin.sol | YES | NatSpec added to _claimCoinflipShortfall and _consumeCoinflipShortfall |
| CMT-053 | BurnieCoin.sol | YES | Vault path documented in _mint and _burn @dev |
| CMT-054 | DegenerusStonk.sol | YES | NatSpec added to _transfer, inline comment added |
| CMT-055 | DegenerusStonk.sol | YES | @custom:reverts Unauthorized added to transfer/transferFrom |
| CMT-056 | StakedDegenerusStonk.sol | YES | DGNRS -> sDGNRS in 3 NatSpec lines |
| CMT-057 | WrappedWrappedXRP.sol | PARTIAL | Line 19 fixed but line 279 still says "Wrapping is disabled" |
| CMT-058 | WrappedWrappedXRP.sol | NO | VaultAllowanceSpent event NatSpec NOT in diff |

### Known Partial/Unfixed Items for Phase 40

1. **CMT-003** (GameStorage.sol): Misplaced SLOT 1 header -- not in diff. May have been deferred. Phase 40 should verify and re-flag if still present.
2. **CMT-057** (WrappedWrappedXRP.sol): PARTIAL fix -- contract-level header fixed (line 19) but section header (line 279) still says "Wrapping is disabled."
3. **CMT-058** (WrappedWrappedXRP.sol): VaultAllowanceSpent event NatSpec NOT fixed in diff. Phase 40 should verify and re-flag.
4. **rngLocked removal** (BurnieCoin.sol): New code change -- `if (degenerusGame.rngLocked()) return;` removed from both shortfall functions. New NatSpec added referencing "BurnieCoinflip blocks auto-rebuy players during RNG lock." Verify this accurately describes the new architecture.

## State of the Art

### Changes Since v3.1 Affecting These Contracts

| Change | Contracts Affected | Impact on Comments |
|--------|-------------------|-------------------|
| v3.1 comment fixes applied (uncommitted) | All 7 contracts | 27 of 30 findings addressed in diff |
| rngLocked removal from shortfall paths | BurnieCoin.sol | Code behavior changed; new NatSpec added |
| Decimator claim expiry removal (commit 19f5bc60) | Not directly in these 7 | No direct impact on Phase 40 scope |
| futurePrizePoolTotalView removed | DegenerusGame.sol | Function and orphaned NatSpec both gone |
| jackpotPhase() removed from interface | DegenerusAdmin.sol | Interface simplified |

### v3.1 Approach (Flag-Only) vs v3.2 Approach

Both use the same flag-only methodology -- produce a findings list without making code changes. The key difference is:
- **v3.1** was scanning contracts that had NOT been modified since Phase 29 (v3.0)
- **v3.2** is scanning contracts that HAVE been modified (v3.1 fixes applied + rngLocked removal)

This means v3.2 must verify that modifications introduced no new issues, in addition to doing a fresh independent scan.

## Open Questions

1. **CMT-003 disposition**
   - What we know: The misplaced SLOT 1 header in GameStorage.sol was not fixed in the working tree diff.
   - What's unclear: Whether this was intentionally deferred or accidentally missed.
   - Recommendation: Re-scan the storage layout section. If the header is still misplaced, re-flag it. The scan should not assume it was intentionally deferred.

2. **Jackpot block deletion adequacy**
   - What we know: CMT-006/007/008 were all addressed by deleting the entire 12-line jackpot payout block comment from DegenerusGame.sol.
   - What's unclear: Whether the deletion leaves a gap in documentation -- there is now no overview comment before the admin reward vault section.
   - Recommendation: During fresh scan, evaluate whether the code in this region is self-documenting enough without the block comment, or whether a corrected (not stale) block comment should be recommended.

3. **BurnieCoin rngLocked comment completeness**
   - What we know: Two shortfall functions had rngLocked checks removed and new NatSpec added.
   - What's unclear: Whether any OTHER comments in BurnieCoin still reference the old rngLocked pattern.
   - Recommendation: grep for "rngLock" in BurnieCoin comments during the scan.

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
| CMT-02 | Core game contract comments verified | manual-only | N/A -- requires reading and cross-referencing NatSpec against code behavior | N/A |
| CMT-03 | Token contract comments verified | manual-only | N/A -- requires reading and cross-referencing NatSpec against code behavior | N/A |

**Justification for manual-only:** This phase verifies the semantic accuracy of human-written English comments against proven code behavior. No automated tool can determine whether a NatSpec description correctly captures a function's intent, parameter semantics, or revert conditions. The verification requires reading each comment in context and comparing against the code it annotates.

### Sampling Rate
- **Per task commit:** Review findings document for completeness -- every function has a verdict, every v3.1 finding has a fix status
- **Per wave merge:** Cross-check that all 7 contracts are covered, no files missed
- **Phase gate:** Both CMT-02 and CMT-03 have explicit verdicts with evidence

### Wave 0 Gaps
None -- no test infrastructure needed. This is a documentation audit phase producing findings reports.

## Sources

### Primary (HIGH confidence)
- contracts/ directory -- all 7 target Solidity files read, line counts and NatSpec density verified
- audit/v3.1-findings-31-core-game-contracts.md -- 12 findings with full details
- audit/v3.1-findings-34-token-contracts.md -- 18 findings with full details
- audit/v3.1-findings-consolidated.md -- master summary (84 findings total)
- `git diff` output for all 7 contracts -- exact changes from v3.1 fixes verified
- .planning/phases/29-comment-documentation-correctness/29-RESEARCH.md -- prior methodology reference

### Secondary (MEDIUM confidence)
- .planning/REQUIREMENTS.md -- CMT-02, CMT-03 requirement definitions
- .planning/PROJECT.md -- key decisions table, known issues

## Metadata

**Confidence breakdown:**
- Scope assessment: HIGH -- all 7 contracts enumerated, line counts verified, NatSpec density measured, v3.1 fix diffs analyzed
- Fix verification baseline: HIGH -- all 30 v3.1 findings mapped to diffs, partial/missing fixes identified before scan begins
- Methodology: HIGH -- established in Phase 29 (v3.0) and Phase 31-34 (v3.1), same approach with fix-verification overlay
- Completeness estimate: HIGH -- fresh scan of 7,415 lines is manageable in 2 plans; prior findings provide efficient cross-reference

**Research date:** 2026-03-19
**Valid until:** 2026-04-18 (30 days -- stable domain, contracts are pre-audit frozen)
