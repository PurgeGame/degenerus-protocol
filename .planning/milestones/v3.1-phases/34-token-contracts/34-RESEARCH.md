# Phase 34: Token Contracts - Research

**Researched:** 2026-03-19
**Domain:** Solidity NatSpec/inline comment verification + intent drift detection for 4 token contracts
**Confidence:** HIGH

## Summary

Phase 34 audits the NatSpec and inline comments of 4 token contracts totaling 2,191 lines: BurnieCoin.sol (1,065 lines), StakedDegenerusStonk.sol (514 lines), DegenerusStonk.sol (223 lines), and WrappedWrappedXRP.sol (389 lines). The deliverable is a per-batch findings file listing every comment inaccuracy and intent drift item, each with what/why/suggestion. No code changes are made.

Only 1 of the 4 contracts was modified after Phase 29: DegenerusStonk.sol received commit fd9dbad1 (lowering the VRF stall threshold from 20h to 5h for `unwrapTo` blocking). The NatSpec was updated in the same commit, so the stale NatSpec was fixed at the code level. The other 3 contracts (BurnieCoin, StakedDegenerusStonk, WrappedWrappedXRP) have NOT been modified since Phase 29.

Phase 29 (commit 9238faf2) verified all 4 token contracts with 0 discrepancies and 0 missing NatSpec across 82 functions. However, Phase 29 was a DOC-01/DOC-02 function-level pass, not a warden-readability and intent-drift review. The v3.1 second pass applies deeper scrutiny: checking block comments, section headers, storage layout documentation, orphaned NatSpec, and cross-contract reference accuracy. During research, several pre-identified issues surfaced that Phase 29 did not catch -- most notably orphaned NatSpec blocks in BurnieCoin.sol (DATA TYPES section documenting structs that live in BurnieCoinflip, BOUNTY STATE section documenting variables that live in BurnieCoinflip) and sDGNRS/DGNRS naming inconsistency in StakedDegenerusStonk.sol pool function NatSpec.

**Primary recommendation:** Split work into 2 plans. BurnieCoin.sol (1,065 lines, 215 NatSpec tags, 44 functions) is the largest contract with the most complex review surface (decimator integration, quest routing, vault escrow, coinflip proxy, orphaned NatSpec blocks). DegenerusStonk (223 lines) + StakedDegenerusStonk (514 lines) + WrappedWrappedXRP (389 lines) together total 1,126 lines and share the second plan, which also handles findings file finalization. The DGNRS/sDGNRS pair should be reviewed together since they cross-reference each other.

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| CMT-04 | All NatSpec and inline comments in token contracts (BurnieCoin, StakedDegenerusStonk, DegenerusStonk, WrappedWrappedXRP) are accurate and warden-ready | 2,191 total lines across 4 contracts. 474 NatSpec tags total, ~659 comment lines, 97 functions. Only DegenerusStonk.sol modified post-Phase-29 (1 commit: fd9dbad1 changed VRF stall threshold from 20h to 5h, NatSpec updated in same commit). Phase 29 verified all 82 public/external functions as MATCH, but did not audit block comments, section headers, or orphaned NatSpec patterns. Pre-identified issues include orphaned DATA TYPES and BOUNTY STATE NatSpec blocks in BurnieCoin.sol, and DGNRS/sDGNRS naming inconsistency in StakedDegenerusStonk.sol. |
| DRIFT-04 | Token contracts reviewed for vestigial logic, unnecessary restrictions, and intent drift | Key areas to check: (1) BurnieCoin.sol orphaned struct NatSpec from coinflip split (lines 220-226), (2) BurnieCoin.sol orphaned bounty state NatSpec from coinflip split (lines 333-361 -- describes state variables that live in BurnieCoinflip.sol), (3) BurnieCoin.sol `onlyAdmin` modifier reusing `OnlyGame()` error -- is this vestigial or intentional gas optimization?, (4) StakedDegenerusStonk.sol pool NatSpec naming sDGNRS vs DGNRS inconsistency (lines 300, 304, 327), (5) DegenerusStonk.sol `_transfer` blocks transfers to `address(this)` without NatSpec explaining why, (6) BurnieCoin.sol `burnCoin` @dev says "DegenerusGame, game, or affiliate" -- redundant and potentially confusing. |
</phase_requirements>

## Standard Stack

This phase does not introduce any libraries or tools. It is a purely manual audit task using existing project infrastructure.

### Core
| Tool | Purpose | Why Standard |
|------|---------|--------------|
| Solidity source files | Primary verification target | contracts/ directory is source of truth (per project memory: NEVER read from degenerus-contracts/ or testing/contracts/) |
| Phase 31-33 findings files | Pattern reference for findings format | audit/v3.1-findings-31-core-game-contracts.md, audit/v3.1-findings-32-game-modules-batch-a.md, audit/v3.1-findings-33-game-modules-batch-b.md establish CMT/DRIFT numbering, severity conventions, and format |
| Git history | Identify post-Phase-29 changes | Commit fd9dbad1 changed DegenerusStonk.sol after Phase 29; other 3 token contracts unchanged |

### Ground Truth Sources (for cross-reference)
| Source | Location | What It Proves |
|--------|----------|---------------|
| Phase 31 findings | audit/v3.1-findings-31-core-game-contracts.md | Established format: CMT-NNN / DRIFT-NNN with what/where/why/suggestion/category/severity. Phase 31: CMT-010, DRIFT-002. |
| Phase 32 findings | audit/v3.1-findings-32-game-modules-batch-a.md | Phase 32 ended at CMT-024, DRIFT-002 (0 new drift). Orphaned NatSpec pattern established (CMT-020). |
| Phase 33 findings | audit/v3.1-findings-33-game-modules-batch-b.md | Phase 33 ended at CMT-040, DRIFT-003. Phase 34 continues at CMT-041, DRIFT-004. |
| Phase 29 token NatSpec | git show 9238faf2:audit/v3.0-doc-peripheral-natspec.md | Phase 29 verified 82 functions across 4 token contracts. All MATCH, 0 DISCREPANCY, 0 MISSING. Inline comment review also clean. But did not audit block comments, orphaned NatSpec, or intent drift. |
| KNOWN-ISSUES.md | audit/KNOWN-ISSUES.md | Design decisions documented for wardens |

## Architecture Patterns

### Contract File Inventory (by size, for work ordering)

```
contracts/BurnieCoin.sol                    1,065 lines  (215 NatSpec tags, ~270 comment lines, 44 functions) [NO POST-PHASE-29 CHANGES]
contracts/StakedDegenerusStonk.sol            514 lines  (107 NatSpec tags, ~168 comment lines, 23 functions) [NO POST-PHASE-29 CHANGES]
contracts/WrappedWrappedXRP.sol               389 lines  (111 NatSpec tags, ~141 comment lines, 16 functions) [NO POST-PHASE-29 CHANGES]
contracts/DegenerusStonk.sol                  223 lines  (41 NatSpec tags, ~80 comment lines, 14 functions)  [POST-PHASE-29 CHANGES x1]
                                            -----
Total:                                      2,191 lines  (474 NatSpec tags, ~659 comment lines, 97 functions)
```

### Token Contract Dependency Structure

```
BurnieCoin.sol (BURNIE)
  - Standalone ERC20 with game integration
  - References: GAME, QUESTS, COINFLIP, VAULT, AFFILIATE, ADMIN via ContractAddresses
  - Key patterns: vault escrow (virtual mint allowance), coinflip shortfall auto-claim,
    decimator burn, quest routing hub

StakedDegenerusStonk.sol (sDGNRS)
  - Soulbound token backed by ETH + stETH + BURNIE reserves
  - References: GAME, DGNRS, COIN (BURNIE), COINFLIP, STETH_TOKEN via ContractAddresses
  - Key patterns: pre-minted pools, proportional burn, ETH-preferred payout, coinflip claim on burn

DegenerusStonk.sol (DGNRS)
  - Transferable ERC20 wrapper around sDGNRS
  - References: SDGNRS, COIN, STETH_TOKEN, GAME, CREATOR via ContractAddresses
  - Key patterns: burn-through to sDGNRS, creator-only unwrapTo with VRF stall guard

WrappedWrappedXRP.sol (WWXRP)
  - Joke ERC20 that may or may not be backed by wXRP
  - References: WXRP, GAME, COIN, COINFLIP, VAULT via ContractAddresses
  - Key patterns: unbacked mintPrize, first-come-first-served unwrap, vault mint allowance
```

### Post-Phase-29 Code Changes (Critical Context)

| Contract | Commit | Changes | Impact on Comments |
|----------|--------|---------|--------------------|
| DegenerusStonk.sol | fd9dbad1 | Changed VRF stall threshold from 20h to 5h for `unwrapTo` blocking. | NatSpec on `unwrapTo` (line 146) UPDATED: now says "(>5h)" instead of "(>20h)". Inline comment at line 150 also updated. Code at line 151 matches: `> 5 hours`. No stale references. |
| BurnieCoin.sol | (none) | No changes since Phase 29. | Full re-review with v3.1 warden-readability lens. |
| StakedDegenerusStonk.sol | (none) | No changes since Phase 29. | Full re-review with v3.1 warden-readability lens. |
| WrappedWrappedXRP.sol | (none) | No changes since Phase 29. | Full re-review with v3.1 warden-readability lens. |

### Pre-Identified Issues (from research read-through)

These are potential findings spotted during research that need formal verification during the audit:

**BurnieCoin.sol:**

1. **Orphaned DATA TYPES section (lines 213-227):** The "DATA TYPES" section header promises "Packed structs for gas-efficient storage" but contains only NatSpec for two data types -- a "Leaderboard entry" struct (lines 220-222) and an "Outcome record" struct (lines 224-226) -- with NO actual struct declarations following. Only one struct exists in BurnieCoin.sol: `Supply` at line 196, which is in the ERC20 STATE section. The documented leaderboard/outcome structs were moved to BurnieCoinflip.sol during the coinflip split. A warden seeing this section would look for struct definitions that don't exist.

2. **Orphaned BOUNTY STATE section (lines 333-361):** The bounty section header describes the bounty pool mechanics (accumulation, arming, payout), a STORAGE LAYOUT table (slots 17-18 for currentBounty/biggestFlipEver/bountyOwedTo), and NatSpec for three state variables -- but none of these variables are declared in BurnieCoin.sol. They live in BurnieCoinflip.sol (lines 161-163). The storage layout reference to slots 17-18 is also incorrect for BurnieCoin's storage. A warden would be confused by documentation for state that doesn't exist in this contract.

3. **`onlyAdmin` modifier reuses `OnlyGame()` error (line 663):** The `onlyAdmin` modifier reverts with `OnlyGame()` when the caller is not ADMIN. The inline comment on `burnForCoinflip` (line 519) acknowledges "Reusing error for simplicity" for the coinflip guard, but the `onlyAdmin` modifier at line 663 has no such acknowledgment. A warden would see `OnlyGame()` reverted from an admin-gated function and question whether the access control is correct.

4. **`burnCoin` @dev says "DegenerusGame, game, or affiliate" (line 854):** The NatSpec lists "DegenerusGame, game" which are the same thing, making it redundant and potentially confusing. Should say "DegenerusGame or affiliate" (matching onlyTrustedContracts).

**StakedDegenerusStonk.sol:**

5. **`transferFromPool` NatSpec says "Transfer DGNRS" (line 300):** This is the sDGNRS contract, so the NatSpec should say "Transfer sDGNRS." The tokens being transferred from pools are sDGNRS tokens held by the contract. Similarly, `transferBetweenPools` at line 327 says "Transfer DGNRS between two reward pools" -- should be "sDGNRS". The `@param amount` at line 304 also says "DGNRS" instead of "sDGNRS".

### Recommended Plan Split

Based on contract sizes, NatSpec density, and pre-identified issue concentration:

**Plan 1 (Wave 1): BurnieCoin.sol (1,065 lines)**
- Largest token contract with most complex review surface
- 215 NatSpec tags, 44 functions
- Orphaned DATA TYPES and BOUNTY STATE sections need careful flagging
- Decimator integration, quest routing hub, vault escrow, coinflip proxy functions
- Creates the batch findings file with header

**Plan 2 (Wave 1, sequential): DegenerusStonk + StakedDegenerusStonk + WrappedWrappedXRP + Finalize (1,126 lines combined)**
- DegenerusStonk.sol (223 lines, 41 NatSpec tags, 14 functions): 1 post-Phase-29 change, smallest contract
- StakedDegenerusStonk.sol (514 lines, 107 NatSpec tags, 23 functions): sDGNRS/DGNRS naming issue in pool NatSpec
- WrappedWrappedXRP.sol (389 lines, 111 NatSpec tags, 16 functions): joke token, straightforward
- Finalize: update summary counts, cross-check all 4 contract sections, verify numbering

### Finding Numbering Continuation

Phase 31 ended at: CMT-010, DRIFT-002
Phase 32 ended at: CMT-024, DRIFT-002 (no new DRIFT)
Phase 33 ended at: CMT-040, DRIFT-003
Phase 34 starts at: CMT-041, DRIFT-004

### Findings File Format

```markdown
# Phase 34 Findings: Token Contracts

**Date:** 2026-03-19
**Scope:** BurnieCoin, StakedDegenerusStonk, DegenerusStonk, WrappedWrappedXRP
**Pass:** v3.1 second independent review (v3.0 Phase 29 was first pass)
**Mode:** Flag-only -- no code changes

## Summary

| Contract | CMT findings | DRIFT findings | Total |
|----------|-------------|----------------|-------|
| BurnieCoin.sol | X | Y | Z |
| StakedDegenerusStonk.sol | X | Y | Z |
| DegenerusStonk.sol | X | Y | Z |
| WrappedWrappedXRP.sol | X | Y | Z |
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

Same methodology as Phases 31-33, adapted for token contracts:

**CMT-04 approach (comment accuracy):**
1. For each contract, read every NatSpec tag (@notice, @dev, @param, @return, @custom) and every inline // comment
2. For each comment, verify it matches actual code behavior in the current HEAD
3. Focus on warden-readability: "Would a C4A warden reading this be misled?"
4. Flag any mismatch as a finding with what/why/suggestion
5. Pay special attention to BurnieCoin.sol block comments and section headers -- the DATA TYPES and BOUNTY STATE sections are prime orphaned NatSpec
6. Verify DegenerusStonk.sol post-Phase-29 NatSpec update completeness (fd9dbad1 changed 20h to 5h)

**DRIFT-04 approach (intent drift):**
1. Scan for vestigial references to features that were moved to BurnieCoinflip during the coinflip split
2. Check for error code reuse that may confuse wardens (OnlyGame() reuse pattern)
3. Look for sDGNRS/DGNRS naming confusion in NatSpec across the wrapper pair
4. Check for unnecessary restrictions or guards that no longer serve their original purpose
5. Flag any drift as a finding with what/why/suggestion

### Anti-Patterns to Avoid

- **Rubber-stamping Phase 29 verdicts:** Phase 29 verified function-level NatSpec (DOC-01) and inline comments (DOC-02). It did NOT check block comments, section headers, storage layout documentation, or orphaned NatSpec patterns. The orphaned DATA TYPES and BOUNTY STATE sections in BurnieCoin.sol demonstrate that Phase 29's "all MATCH" verdict was scoped differently than v3.1.
- **Assuming orphaned NatSpec is harmless:** Orphaned NatSpec that describes structures, variables, or behavior from another contract is actively misleading. A warden reading BurnieCoin.sol would expect to find the bounty variables and leaderboard structs described in the section headers. Their absence creates confusion about the contract's actual storage layout and functionality.
- **Confusing sDGNRS (soulbound) with DGNRS (wrapper):** The StakedDegenerusStonk contract holds sDGNRS tokens in pools and transfers them to recipients. NatSpec that says "DGNRS" when it means "sDGNRS" is materially misleading because DGNRS is a separate, transferable contract. A warden might think pool tokens are transferable DGNRS rather than soulbound sDGNRS.
- **Ignoring error code reuse pattern:** BurnieCoin.sol reuses OnlyGame() for coinflip access control (acknowledged at line 519) and admin access control (unacknowledged at line 663). This is a deliberate gas optimization but the inconsistent documentation makes it look like a bug.
- **Scope creep into code fixes:** If a real bug or optimization is found, document it as a finding but do NOT attempt code changes. This is flag-only.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Finding post-Phase-29 changes | Manual git log | `git diff 9238faf2..HEAD -- contracts/DegenerusStonk.sol` | Precise diff of what changed after Phase 29 |
| Counting NatSpec tags | Manual counting | `grep -cE '@dev\|@notice\|@param\|@return' contracts/File.sol` | Accurate enumeration |
| Finding orphaned NatSpec | Reading all comments manually | `grep -n '/// @notice\|/// @dev' FILE` then diff with function/struct/variable declarations | Quick identification of detached NatSpec |
| Verifying struct presence | Scrolling through file | `grep -n 'struct\b' contracts/BurnieCoin.sol` | Confirms only Supply struct exists (DATA TYPES section is orphaned) |
| Finding bounty vars | Scrolling | `grep -n 'currentBounty\|biggestFlipEver\|bountyOwedTo' contracts/BurnieCoin.sol` | Confirms bounty vars are only mentioned in comments, not declared |
| Cross-checking DGNRS naming | Manual reading | `grep -n 'DGNRS' contracts/StakedDegenerusStonk.sol` | Lists all instances for naming consistency review |

## Common Pitfalls

### Pitfall 1: BurnieCoin Orphaned Documentation from Coinflip Split
**What goes wrong:** BurnieCoin.sol contains section headers, NatSpec, and storage layout documentation for structs and variables that were moved to BurnieCoinflip.sol during a refactoring split. The documentation remained but the code moved.
**Why it happens:** When BurnieCoinflip was extracted as a separate contract, the function-level code was moved but the surrounding block comments and NatSpec were left behind in BurnieCoin.sol.
**How to avoid:** For every NatSpec block in BurnieCoin.sol that describes a struct, variable, or storage slot, verify the declaration actually exists in the same file. Key areas: DATA TYPES section (lines 213-227), BOUNTY STATE section (lines 333-361), and the storage slot numbers referenced in section headers.
**Warning signs:** NatSpec blocks followed by blank lines or other section headers instead of code declarations.

### Pitfall 2: sDGNRS/DGNRS Naming Confusion in Pool Functions
**What goes wrong:** StakedDegenerusStonk.sol NatSpec says "DGNRS" when describing sDGNRS operations, because both tokens share the "Degenerus Stonk" brand and DGNRS is the more commonly referenced symbol.
**Why it happens:** When sDGNRS was split from the original DGNRS monolith, some NatSpec retained the "DGNRS" name for pool operations even though the sDGNRS contract is the one holding and distributing pool tokens.
**How to avoid:** For every function in StakedDegenerusStonk.sol, verify the NatSpec uses "sDGNRS" (not "DGNRS") when referring to the tokens this contract manages. Check transferFromPool, transferBetweenPools, and any @param/@return tags.
**Warning signs:** NatSpec saying "Transfer DGNRS from a reward pool" in the sDGNRS contract.

### Pitfall 3: OnlyGame Error Reuse Pattern
**What goes wrong:** BurnieCoin.sol has a dedicated `OnlyGame()` error but reuses it for non-game access control gates (coinflip at line 519, admin at line 663). Only the coinflip reuse is acknowledged with an inline comment.
**Why it happens:** Gas optimization -- defining separate errors increases bytecode size. The developer chose to reuse OnlyGame() for multiple access control failures.
**How to avoid:** Flag the undocumented reuse at the onlyAdmin modifier (line 663) while noting the documented pattern at burnForCoinflip (line 519). Both should be consistent: either both document the reuse or neither does.
**Warning signs:** A warden seeing `revert OnlyGame()` in a function gated by `onlyAdmin` would suspect incorrect access control.

### Pitfall 4: Missing NatSpec on Private Functions
**What goes wrong:** BurnieCoin.sol has two private helper functions (`_claimCoinflipShortfall` at line 580 and `_consumeCoinflipShortfall` at line 593) with no NatSpec. These are critical for understanding the auto-claim pattern.
**Why it happens:** Phase 29 checked external/public function NatSpec but did not audit private helpers.
**How to avoid:** Note that missing NatSpec on private functions is lower severity than on public/external functions. Flag only if the function behavior is non-obvious and a warden reading the code would benefit from documentation.
**Warning signs:** Private functions called from multiple public functions (both are called from transfer/transferFrom/burnCoin/decimatorBurn flows).

### Pitfall 5: Token Contract Cross-References
**What goes wrong:** The 4 token contracts reference each other extensively. StakedDegenerusStonk describes "DGNRS wrapper" patterns. DegenerusStonk describes "sDGNRS backing." BurnieCoin describes "vault" operations. If any cross-reference is stale, it misleads wardens about inter-contract behavior.
**How to avoid:** For each cross-contract reference in NatSpec, verify it matches the current behavior of the referenced contract. Key references: BurnieCoin vault escrow pattern, sDGNRS burn-through delegation, DGNRS unwrapTo VRF guard.
**Warning signs:** References to "20 hours" (old VRF stall threshold) anywhere outside DegenerusStonk.sol.

## Code Examples

### Verifying Post-Phase-29 Changes

```bash
# Only DegenerusStonk.sol changed (fd9dbad1: 20h -> 5h VRF stall threshold)
git diff 9238faf2..HEAD -- contracts/DegenerusStonk.sol
# Shows: line 146 @dev "20h" -> "5h", line 151 code "20 hours" -> "5 hours"

# Verify other 3 contracts unchanged
git diff 9238faf2..HEAD -- contracts/BurnieCoin.sol
# (should be empty)
git diff 9238faf2..HEAD -- contracts/StakedDegenerusStonk.sol
# (should be empty)
git diff 9238faf2..HEAD -- contracts/WrappedWrappedXRP.sol
# (should be empty)
```

### Verifying Orphaned NatSpec in BurnieCoin

```bash
# Check if DATA TYPES section structs exist
grep -n 'struct\b' contracts/BurnieCoin.sol
# Returns only: 196:    struct Supply {
# The Leaderboard entry and Outcome record NatSpec (lines 220-226) have no structs

# Check if BOUNTY STATE variables exist
grep -n 'currentBounty\|biggestFlipEver\|bountyOwedTo' contracts/BurnieCoin.sol
# Returns only comment references in the block header, no actual variable declarations
# These variables live in BurnieCoinflip.sol lines 161-163
```

### Verifying sDGNRS/DGNRS Naming

```bash
# All DGNRS references in StakedDegenerusStonk.sol
grep -n 'DGNRS' contracts/StakedDegenerusStonk.sol
# Lines 300, 304, 327 say "DGNRS" in pool function NatSpec -- should be "sDGNRS"
```

## State of the Art

This section is not applicable to a documentation verification phase. No libraries, frameworks, or evolving standards are involved. The Solidity 0.8.34 compiler and NatSpec specification are stable.

## Open Questions

1. **BurnieCoin orphaned sections: remove vs relocate?**
   - What we know: The DATA TYPES and BOUNTY STATE sections in BurnieCoin.sol document structures and variables that live in BurnieCoinflip.sol. The section headers themselves reference accurate behavior (the bounty mechanics are real), but the documentation is in the wrong contract.
   - What's unclear: Should the finding suggest removal (simpler) or relocation to BurnieCoinflip.sol (more complete)?
   - Recommendation: Suggest removal from BurnieCoin.sol. BurnieCoinflip.sol already has its own documentation. Maintaining duplicate documentation across contracts creates staleness risk. The planner should instruct the auditor to recommend removal.

2. **BurnieCoin coinflipAutoRebuyInfo missing `startDay` return param**
   - What we know: The `coinflipAutoRebuyInfo` view function at line 308-312 returns `(bool enabled, uint256 stopAmount, uint256 carry)` per its NatSpec, but the underlying `IBurnieCoinflip.coinflipAutoRebuyInfo` returns 4 values including `uint48 startDay`. BurnieCoin discards `startDay` with `, )` on line 311.
   - What's unclear: Whether the missing `@return` for `startDay` (or lack of acknowledgment of the discarded value) constitutes a finding.
   - Recommendation: Low-severity or non-finding -- the function signature explicitly shows only 3 return values. The NatSpec matches the public interface. But a warden might wonder why `startDay` is discarded.

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
| CMT-04 | NatSpec and inline comments in 4 token contracts are accurate and warden-ready | manual-only | N/A -- requires reading and cross-referencing each comment against code | N/A |
| DRIFT-04 | Token contracts reviewed for vestigial logic, unnecessary restrictions, and intent drift | manual-only | N/A -- requires understanding designer intent vs actual behavior | N/A |

**Justification for manual-only:** This phase verifies the semantic accuracy of human-written English comments against code behavior and design intent. There is no automated tool that can determine whether a NatSpec description would mislead a C4A warden. The verification requires understanding cross-contract interactions, the coinflip split history, token naming conventions, and the protocol's intended design.

### Sampling Rate
- **Per task commit:** Review findings file for completeness -- every function and block comment in the target contract(s) should be covered
- **Per wave merge:** Cross-check that all 4 contracts are covered with no files missed
- **Phase gate:** CMT-04 and DRIFT-04 both have explicit verdicts; a per-batch findings file exists with what/why/suggestion for every item

### Wave 0 Gaps
None -- no test infrastructure needed. This is a documentation/findings-only audit phase producing a findings markdown file.

## Sources

### Primary (HIGH confidence)
- contracts/BurnieCoin.sol -- 1,065 lines, read in full during research. Orphaned NatSpec blocks identified at lines 213-227 (DATA TYPES) and 333-361 (BOUNTY STATE). OnlyGame error reuse pattern at lines 519, 663.
- contracts/StakedDegenerusStonk.sol -- 514 lines, read in full during research. DGNRS/sDGNRS naming inconsistency at lines 300, 304, 327.
- contracts/DegenerusStonk.sol -- 223 lines, read in full during research. Post-Phase-29 VRF stall threshold change from 20h to 5h verified clean.
- contracts/WrappedWrappedXRP.sol -- 389 lines, read in full during research. No pre-identified issues.
- contracts/BurnieCoinflip.sol -- bounty state variables confirmed at lines 161-163 (currentBounty, biggestFlipEver, bountyOwedTo), confirming BurnieCoin.sol orphaned NatSpec.
- git diff 9238faf2..HEAD -- verified 1 contract changed (DegenerusStonk.sol), 3 unchanged since Phase 29.
- git show 9238faf2:audit/v3.0-doc-peripheral-natspec.md -- Phase 29 token contract results: 82 functions verified, all MATCH, 0 DISCREPANCY, 0 MISSING.
- audit/v3.1-findings-31-core-game-contracts.md -- Phase 31 findings format and numbering reference.
- audit/v3.1-findings-32-game-modules-batch-a.md -- Phase 32 findings continuation reference.
- audit/v3.1-findings-33-game-modules-batch-b.md -- Phase 33 findings endpoint (CMT-040, DRIFT-003). Phase 34 starts at CMT-041, DRIFT-004.

### Secondary (MEDIUM confidence)
- .planning/PROJECT.md -- Key decisions table (sDGNRS/DGNRS split rationale, unwrapTo VRF guard)
- .planning/STATE.md -- Accumulated context from Phases 31-33 (post-Phase-29 NatSpec update patterns)

## Metadata

**Confidence breakdown:**
- Scope assessment: HIGH -- all 4 contract files read in full, line/NatSpec/function counts verified via grep, post-Phase-29 changes identified via git diff with exact commit
- Post-Phase-29 change analysis: HIGH -- only 1 commit (fd9dbad1) affecting token contracts, diff reviewed in full, NatSpec update verified as complete
- Pre-identified issues: HIGH -- orphaned NatSpec blocks in BurnieCoin.sol verified by cross-referencing against BurnieCoinflip.sol variable declarations; sDGNRS/DGNRS naming inconsistency verified by grep
- Methodology: HIGH -- standard NatSpec/inline review approach proven in Phases 31-33, reusing established findings format
- Plan structure: HIGH -- contract sizes support the 2-plan split (1,065 + 1,126 lines)
- Completeness of pre-identified issues: MEDIUM -- the 5 pre-identified issues are verified, but full review of 474 NatSpec tags and ~659 comment lines may surface additional findings

**Research date:** 2026-03-19
**Valid until:** 2026-04-18 (30 days -- stable domain, contracts not expected to change during audit prep)
