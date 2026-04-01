# Phase 41: Comment Scan -- Peripheral + Remaining - Research

**Researched:** 2026-03-19
**Domain:** Solidity comment correctness audit (NatSpec, inline, block comments)
**Confidence:** HIGH

## Summary

Phase 41 is a flag-only comment audit covering 12 contracts: 5 peripheral (BurnieCoinflip, DegenerusVault, DegenerusAffiliate, DegenerusQuests, DegenerusJackpots), 5 remaining/utility (DegenerusDeityPass, DegenerusTraitUtils, DeityBoonViewer, ContractAddresses, Icons32Data), and 2 interfaces (IBurnieCoinflip, IDegenerusGame). Total scope: ~6,914 lines of Solidity.

The v3.1 comment audit (Phase 35) found 23 findings across these same contracts. Since then, the protocol team has applied fixes to many of those findings AND made functional code changes (rngLocked removal, claimCoinflipsTakeProfit removal, QUEST_TYPE_RESERVED removal, quest type ID renumbering). These code changes create new comment drift risks that were not present during v3.1. The v3.2 re-scan must verify that (a) v3.1 fixes are correct and complete, (b) new code changes have not introduced new comment inaccuracies, and (c) interface NatSpec matches updated implementations.

**Primary recommendation:** Audit each contract against its CURRENT working-tree state (not last commit), paying special attention to the interface-implementation NatSpec mismatch on rngLocked revert annotations. The 5 unchanged contracts (DeityPass, TraitUtils, DeityBoonViewer) can be fast-tracked with delta-only review since v3.1 found 0 issues in them.

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| CMT-04 | Peripheral contracts -- all comments verified (BurnieCoinflip, DegenerusVault, DegenerusAffiliate, DegenerusQuests, DegenerusJackpots) | All 5 contracts have uncommitted code changes since v3.1. Diff analysis below identifies 14 specific change areas requiring re-verification. v3.1 found 21 findings across these 5 contracts; many have been fixed but completeness must be verified. |
| CMT-05 | Remaining contracts -- all comments verified (DeityPass, TraitUtils, DeityBoonViewer, ContractAddresses, Icons32Data) | DeityPass, TraitUtils, and DeityBoonViewer have zero changes since v3.1 (which found 0 issues). ContractAddresses and Icons32Data have targeted fixes for v3.1 findings CMT-079 and CMT-080. |
</phase_requirements>

## Standard Stack

Not applicable -- this is a manual comment audit phase, not a software implementation phase. No libraries or frameworks are needed.

## Architecture Patterns

### Established Audit Output Format

The v3.1 audit (Phase 35) established the output format. Each finding uses this structure:

```markdown
### CMT-NNN: [Short description]

- **What:** [Precise description of the inaccuracy]
- **Where:** `ContractFile.sol:LINE`
- **Why:** [Why a warden would be misled]
- **Suggestion:** [Specific fix text]
- **Category:** CMT (comment inaccuracy) | DRIFT (intent drift)
- **Severity:** INFO | LOW
```

Each contract section includes a header with review scope (lines, NatSpec tags, comment lines, functions) and change status.

### Contract Grouping for Plans

Based on contract sizes and change density, the following grouping is recommended:

**Plan 1: Peripheral contracts with heavy changes (~3,200 lines)**
- BurnieCoinflip.sol (1,114 lines, 68 changed lines -- heaviest changes: rngLocked removal, takeProfit removal, NatSpec additions)
- DegenerusQuests.sol (1,588 lines, 28 changed lines -- QUEST_TYPE_RESERVED removal, type renumbering, NatSpec fixes)
- DegenerusJackpots.sol (689 lines, 14 changed lines -- BurnieCoin->BurnieCoinflip reference fixes)

**Plan 2: Peripheral contracts with lighter changes + interfaces (~2,514 lines)**
- DegenerusVault.sol (1,050 lines, 17 changed lines -- AFK->afKing fix, takeProfit removal, transferFrom @custom:reverts fix)
- DegenerusAffiliate.sol (848 lines, 5 changed lines -- taper values fix, batch comment fix)
- IBurnieCoinflip.sol (173 lines, 14 removed lines -- takeProfit removal, BUT stale RngLocked annotations remain)
- IDegenerusGame.sol (443 lines, 4 removed lines -- futurePrizePoolTotalView removal)

**Plan 3: Remaining/utility contracts (~1,009 lines, mostly clean)**
- DegenerusDeityPass.sol (392 lines, 0 changes -- v3.1 found 0 issues)
- DegenerusTraitUtils.sol (183 lines, 0 changes -- v3.1 found 0 issues)
- DeityBoonViewer.sol (171 lines, 0 changes -- v3.1 found 0 issues)
- ContractAddresses.sol (37 lines, 2 changed lines -- CMT-079 fix)
- Icons32Data.sol (226 lines, 2 changed lines -- CMT-080 fix)

### Anti-Patterns to Avoid

- **Auto-fixing:** This is a flag-only audit. Produce findings list, do NOT edit contract files.
- **Skipping unchanged contracts:** Even if v3.1 found 0 issues, confirm the contracts remain unchanged. A quick "verified unchanged, 0 new findings" note per contract is required.
- **Missing interface-implementation cross-check:** The interfaces are a critical audit surface -- NatSpec in IBurnieCoinflip and IDegenerusGame must match the actual implementation behavior.

## Don't Hand-Roll

Not applicable -- this is a manual review process, not a software build.

## Common Pitfalls

### Pitfall 1: Interface NatSpec Drift After Implementation Changes

**What goes wrong:** The implementation removes a revert condition (e.g., `rngLocked()` check) but the interface still documents `@custom:reverts RngLocked`.
**Why it happens:** Interface files are often forgotten when implementation changes are made.
**How to avoid:** Cross-reference every `@custom:reverts`, `@param`, and `@return` in IBurnieCoinflip.sol and IDegenerusGame.sol against the current implementation.
**Warning signs:** The diff shows `claimCoinflipsTakeProfit` was removed from both the implementation and the interface, but `@custom:reverts RngLocked` annotations on `claimCoinflips`, `claimCoinflipsFromBurnie`, and `consumeCoinflipsForBurn` remain in the interface while the implementation no longer checks `rngLocked()`.

### Pitfall 2: Partial v3.1 Fix Application

**What goes wrong:** A v3.1 finding is partially fixed (e.g., one location updated but a sister reference in the same file left stale).
**Why it happens:** When fixing NatSpec issues, related references in the same contract can be missed.
**How to avoid:** For each v3.1 finding that was addressed, verify ALL locations mentioned in the finding were updated.
**Warning signs:** DegenerusVault.sol CMT-078 fixed the `@custom:reverts` on `transferFrom` but the `_transfer` @dev at line 286 still says "zero-address checks" (plural) when only `to` is checked.

### Pitfall 3: New Comment Drift From Code Removals

**What goes wrong:** When code is removed (e.g., `claimCoinflipsTakeProfit`, `QUEST_TYPE_RESERVED`), surrounding comments may reference the removed code.
**Why it happens:** Developers remove the function/constant but don't audit all comments that reference it.
**How to avoid:** After identifying removed code, grep for references to the removed symbols in comments across the contract.
**Warning signs:** Check for any remaining references to `claimCoinflipsTakeProfit`, `QUEST_TYPE_RESERVED`, `futurePrizePoolTotalView`, `_diamond`, etc.

### Pitfall 4: Quest Type ID Renumbering Without Comment Updates

**What goes wrong:** Quest type IDs shifted (DECIMATOR went from 5 to 4, LOOTBOX from 6 to 5, etc.) but comments referencing specific type IDs by number remain stale.
**Why it happens:** QUEST_TYPE_RESERVED removal caused all subsequent IDs to shift down by 1. QUEST_TYPE_COUNT changed from 9 to 8.
**How to avoid:** Search for any hardcoded references to old quest type IDs in comments or NatSpec.

## Code Examples

Not applicable -- this phase produces a findings document, not code.

## State of the Art

### v3.1 Findings Status for Phase 41 Contracts

The following table maps each v3.1 finding to its current status based on the uncommitted diff analysis:

| v3.1 Finding | Contract | Status in Working Tree | Notes |
|-------------|----------|----------------------|-------|
| CMT-059 | DegenerusQuests.sol:16 | **FIXED** | Header now says "COIN and COINFLIP contracts" |
| CMT-060 | DegenerusQuests.sol:24 | **FIXED** | `onlyCoinOrGame` reference removed, Security Model rewritten |
| CMT-061 | DegenerusQuests.sol:23 | **FIXED** | Now says "COIN/COINFLIP-gated via `onlyCoin` modifier" |
| CMT-062 | DegenerusQuests.sol:303 | **FIXED** | Now says "Slot 0 is fixed to MINT_ETH (no entropy used)" |
| CMT-063 | DegenerusQuests.sol:284,55 | **FIXED** | Error @notice now says "COIN or COINFLIP"; modifier @dev says "COIN or COINFLIP" |
| CMT-064 | DegenerusQuests.sol:1370 | **FIXED** | Now says "credits streak on slot 0 completion" |
| DRIFT-004 | DegenerusQuests.sol:153 | **FIXED** | `QUEST_TYPE_RESERVED` constant and skip guard both removed |
| CMT-065 | DegenerusJackpots.sol:35 | **FIXED** | Now says "BurnieCoinflip forwards flips" |
| CMT-066 | DegenerusJackpots.sol:164 | **FIXED** | Section header now says "COINFLIP CONTRACT HOOKS / Called by BurnieCoinflip" |
| CMT-067 | DegenerusJackpots.sol:169,173 | **FIXED** | @dev and @custom:access now say "coinflip contract" |
| CMT-068 | DegenerusJackpots.sol:47 | **FIXED** | OnlyCoin error now says "restricted to the coinflip contract" |
| CMT-069 | DegenerusJackpots.sol:19 | **FIXED** | Interface @notice now says "coinflip contract" |
| CMT-070 | DegenerusAffiliate.sol:383 | **FIXED** | @param now says "10000+ triggers linear taper to 25% floor" |
| CMT-071 | DegenerusAffiliate.sol:546 | **FIXED** | Now says "Collect recipients for weighted random winner selection" |
| CMT-072 | BurnieCoinflip.sol:128 | **FIXED** | `JACKPOT_RESET_TIME` constant removed |
| CMT-073 | BurnieCoinflip.sol:224 | **FIXED** | NatSpec added (@dev, @param for operator pattern) |
| CMT-074 | BurnieCoinflip.sol:970 | **FIXED** | "staking removed" vestigial phrase removed |
| CMT-075 | BurnieCoinflip.sol:165 | **FIXED** | Section comment changed to "Last resolved day -- claims can process up to this day" |
| CMT-076 | BurnieCoinflip.sol:1142 | **FIXED** | Now correctly reverts with `NotApproved()` |
| CMT-077 | DegenerusVault.sol:662 | **FIXED** | Now says "afKing mode" instead of "AFK king mode" |
| CMT-078 | DegenerusVault.sol:236 | **PARTIALLY FIXED** | `transferFrom` @custom:reverts fixed, but `_transfer` @dev still says "zero-address checks" (plural) |
| CMT-079 | ContractAddresses.sol:5 | **FIXED** | "All addresses are zeroed in source" comment removed |
| CMT-080 | Icons32Data.sol:28 | **FIXED** | `_diamond` phantom reference removed from block comment |

**Summary:** 22 of 23 v3.1 findings are fully fixed. 1 finding (CMT-078) is partially fixed.

### New Code Changes Requiring Fresh Comment Audit

These changes were NOT present during v3.1 and introduce new comment drift risk:

| Change | Contract | Comment Drift Risk |
|--------|----------|-------------------|
| `rngLocked()` checks removed from claim functions | BurnieCoinflip.sol | **HIGH** -- implementation @dev updated but IBurnieCoinflip.sol still has `@custom:reverts RngLocked` on 3 claim functions (lines 33, 42, 51) |
| `claimCoinflipsTakeProfit` function removed | BurnieCoinflip.sol | MEDIUM -- function and its internal helper `_claimCoinflipsTakeProfit` both removed; verify no remaining references in comments |
| `claimCoinflipsTakeProfit` removed from interface | IBurnieCoinflip.sol | LOW -- cleanly removed from interface |
| `claimCoinflipsTakeProfit` removed from vault interface + function | DegenerusVault.sol | MEDIUM -- `ICoinflipPlayerActions` interface lost the function; `coinClaimCoinflipsTakeProfit` function removed; verify no remaining NatSpec references |
| `QUEST_TYPE_RESERVED` removed, IDs renumbered | DegenerusQuests.sol | MEDIUM -- all type constants shifted down by 1; verify no comments reference old IDs |
| `QUEST_TYPE_COUNT` changed from 9 to 8 | DegenerusQuests.sol | LOW -- verify any comments mentioning "9 quest types" are updated |
| `futurePrizePoolTotalView` removed from interface | IDegenerusGame.sol | LOW -- cleanly removed |
| New PRNG design note added to affiliate | DegenerusAffiliate.sol | LOW -- new comment at line 544; verify accuracy of the PRNG claim |

### Pre-Identified Findings for v3.2 Re-scan

Based on diff analysis, the following are LIKELY new findings (must be verified during audit execution):

**HIGH-probability finding: IBurnieCoinflip stale RngLocked annotations**
- IBurnieCoinflip.sol lines 33, 42, 51 still have `@custom:reverts RngLocked If VRF randomness is currently being resolved`
- The implementation (BurnieCoinflip.sol) no longer checks `rngLocked()` on `claimCoinflips`, `claimCoinflipsFromBurnie`, or `consumeCoinflipsForBurn`
- This is a direct interface-implementation NatSpec mismatch

**MEDIUM-probability finding: DegenerusVault _transfer @dev still plural**
- Line 286: "Internal transfer logic with balance and zero-address checks" -- the plural "checks" implies both from and to are checked, but only `to` is checked
- The `transferFrom` @custom:reverts was fixed (CMT-078 partial), but _transfer @dev was not updated

**MEDIUM-probability finding: DegenerusJackpots OnlyCoin error naming**
- Line 47: Error now says "restricted to the coinflip contract" (singular) but the `onlyCoin` modifier accepts BOTH COIN and COINFLIP (line 150)
- The v3.1 fix changed "coin contract" to "coinflip contract" but the modifier still accepts both -- the fix swung from one inaccuracy to the opposite

## Open Questions

1. **Quest type ID references in NatSpec comments**
   - What we know: IDs shifted down by 1 (DECIMATOR 5->4, LOOTBOX 6->5, etc.)
   - What's unclear: Whether any @dev or inline comments reference specific type ID numbers that are now stale
   - Recommendation: Full grep for numeric quest type references during audit execution

2. **Scope of `claimCoinflipsTakeProfit` removal**
   - What we know: Function removed from BurnieCoinflip, IBurnieCoinflip, DegenerusVault
   - What's unclear: Whether any other comments across the 12 target contracts reference this function
   - Recommendation: Grep for `takeProfit` and `TakeProfit` in NatSpec/comments of all target contracts

3. **New comment on DegenerusAffiliate.sol line 544**
   - What we know: A new inline comment was added: "PRNG is known -- accepted design tradeoff (EV-neutral, manipulation only redistributive between affiliates)"
   - What's unclear: Whether this accurately characterizes the PRNG properties
   - Recommendation: Verify during audit execution by checking the PRNG mechanism

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Hardhat + Foundry |
| Config file | hardhat.config.js, foundry.toml |
| Quick run command | `npx hardhat test` |
| Full suite command | `npx hardhat test && forge test` |

### Phase Requirements -> Test Map

This phase produces a findings document, not code changes. Validation is via completeness review rather than automated tests.

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| CMT-04 | All peripheral contract comments verified | manual-only | N/A -- human review of findings document | N/A |
| CMT-05 | All remaining contract comments verified | manual-only | N/A -- human review of findings document | N/A |

**Manual-only justification:** Comment audit is inherently a semantic review task. Each finding requires reading code context and understanding intent. The deliverable is a findings list, not code changes.

### Sampling Rate
- **Per task commit:** Verify findings count and contract coverage (all 12 contracts present)
- **Per wave merge:** Cross-check findings against known code changes
- **Phase gate:** All 12 contracts have audit sections in findings document

### Wave 0 Gaps
None -- no test infrastructure needed for a manual audit phase.

## Sources

### Primary (HIGH confidence)
- Working tree diff analysis: `git diff HEAD -- contracts/...` for all 12 target contracts
- v3.1 findings document: `audit/v3.1-findings-35-peripheral-contracts.md` (23 findings, fully reviewed)
- Contract source code: Direct file reads of all 12 contracts in current working tree state

### Secondary (MEDIUM confidence)
- Git log history for change provenance and commit messages
- v3.1 consolidated findings: `audit/v3.1-findings-consolidated.md` (for cross-referencing patterns)

## Metadata

**Confidence breakdown:**
- Contract change analysis: HIGH -- direct diff comparison against known v3.1 baseline
- v3.1 finding status: HIGH -- each finding verified against current working tree
- Pre-identified new findings: MEDIUM -- identified from diff analysis but must be verified during execution
- Unchanged contract assessment: HIGH -- git confirms zero changes to DeityPass, TraitUtils, DeityBoonViewer

**Research date:** 2026-03-19
**Valid until:** 2026-03-26 (7 days -- working tree may change)
