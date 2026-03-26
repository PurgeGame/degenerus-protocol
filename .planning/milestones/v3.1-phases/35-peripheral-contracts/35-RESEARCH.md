# Phase 35: Peripheral Contracts - Research

**Researched:** 2026-03-19
**Domain:** Solidity NatSpec/inline comment verification + intent drift detection for 10 peripheral contracts
**Confidence:** HIGH

## Summary

Phase 35 audits the NatSpec and inline comments of 10 peripheral contracts totaling 6,362 lines: BurnieCoinflip.sol (1,154 lines), DegenerusAffiliate.sol (847 lines), DegenerusDeityPass.sol (392 lines), DegenerusQuests.sol (1,598 lines), DegenerusJackpots.sol (689 lines), DegenerusVault.sol (1,061 lines), DegenerusTraitUtils.sol (183 lines), DeityBoonViewer.sol (171 lines), ContractAddresses.sol (39 lines), and Icons32Data.sol (228 lines). The deliverable is a per-batch findings file listing every comment inaccuracy and intent drift item, each with what/why/suggestion. No code changes are made.

None of the 10 contracts were modified after Phase 29 (commit 9238faf2). Verified via `git log 9238faf2..HEAD -- contracts/{file}` returning empty for all 10 files. Phase 29 verified these contracts' function-level NatSpec as part of the DOC-01/DOC-02 pass. The v3.1 second pass applies deeper scrutiny: checking block comments, section headers, storage layout documentation, orphaned NatSpec, cross-contract reference accuracy, and intent drift.

This batch is the largest of the v3.1 audit -- 10 contracts spanning 6,362 lines with 890 NatSpec tags, 1,723 comment lines, and 232 functions. The contracts range widely in complexity from ContractAddresses.sol (39 lines, pure constants, 0 NatSpec tags) to DegenerusQuests.sol (1,598 lines, 249 NatSpec tags, 35 functions). The batch includes 3 large contracts (BurnieCoinflip, DegenerusQuests, DegenerusVault at 1,000+ lines each), 2 medium contracts (DegenerusAffiliate, DegenerusJackpots at 600-900 lines), 1 moderate contract (DegenerusDeityPass at 392 lines), and 4 small contracts (DegenerusTraitUtils, Icons32Data, DeityBoonViewer, ContractAddresses at under 230 lines each).

**Primary recommendation:** Split work into 4 plans based on logical groupings and balanced workload. Plan 1: BurnieCoinflip.sol (1,154 lines -- coinflip system, heaviest review surface, interacts closely with BurnieCoin findings from Phase 34). Plan 2: DegenerusQuests.sol + DegenerusJackpots.sol (2,287 lines combined -- game mechanics peripherals with dense NatSpec). Plan 3: DegenerusAffiliate.sol + DegenerusVault.sol (1,908 lines combined -- reward/vault peripherals with many function NatSpec). Plan 4: DegenerusDeityPass.sol + DegenerusTraitUtils.sol + DeityBoonViewer.sol + ContractAddresses.sol + Icons32Data.sol + finalize findings (1,013 lines combined -- small/simple contracts, finalization).

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| CMT-05 | All NatSpec and inline comments in peripheral contracts (BurnieCoinflip, DegenerusAffiliate, DegenerusDeityPass, DegenerusQuests, DegenerusJackpots, DegenerusVault, DegenerusTraitUtils, DeityBoonViewer, ContractAddresses, Icons32Data) are accurate and warden-ready | 6,362 total lines across 10 contracts. 890 NatSpec tags total, ~1,723 comment lines, 232 functions. None modified post-Phase-29. Phase 29 verified function-level NatSpec (all MATCH, 0 DISCREPANCY), but did not audit block comments, section headers, or cross-contract reference accuracy. BurnieCoinflip.sol was extracted from BurnieCoin.sol (coinflip split) -- same orphaned NatSpec pattern risk as Phase 34. DegenerusVault.sol contains an embedded DegenerusVaultShare contract (adds review complexity). DegenerusDeityPass has minimal NatSpec (13 tags for 31 functions -- many functions lack NatSpec). |
| DRIFT-05 | Peripheral contracts reviewed for vestigial logic, unnecessary restrictions, and intent drift | Key areas: (1) BurnieCoinflip.sol error reuse pattern (_resolvePlayer reverts with OnlyBurnieCoin at line 1142 for operator approval failure), (2) DegenerusAffiliate.sol NatSpec referencing payAffiliate access as "coin or game" -- verify accuracy, (3) DegenerusJackpots.sol coin reference points to COINFLIP address (line 93) -- verify NatSpec aligns, (4) DegenerusVault.sol dual-contract structure (DegenerusVaultShare + DegenerusVault), (5) DegenerusDeityPass.sol -- 31 functions with only 13 NatSpec tags (many undocumented), (6) DegenerusQuests.sol -- quest type constants and reserved type QUEST_TYPE_RESERVED = 4 may be vestigial, (7) Cross-contract references in all 10 peripherals. |
</phase_requirements>

## Standard Stack

This phase does not introduce any libraries or tools. It is a purely manual audit task using existing project infrastructure.

### Core
| Tool | Purpose | Why Standard |
|------|---------|--------------|
| Solidity source files | Primary verification target | contracts/ directory is source of truth (per project memory: NEVER read from degenerus-contracts/ or testing/contracts/) |
| Phase 31-34 findings files | Pattern reference for findings format | audit/v3.1-findings-{31,32,33,34}-*.md establish CMT/DRIFT numbering, severity conventions, and format |
| Git history | Identify post-Phase-29 changes | `git log 9238faf2..HEAD` confirms 0 contracts changed in this batch |

### Ground Truth Sources (for cross-reference)
| Source | Location | What It Proves |
|--------|----------|---------------|
| Phase 34 findings | audit/v3.1-findings-34-token-contracts.md | Phase 34 ended at CMT-058, DRIFT-003. Phase 35 starts at CMT-059, DRIFT-004. |
| Phase 34 BurnieCoin findings | audit/v3.1-findings-34-token-contracts.md | Orphaned NatSpec from coinflip split documented -- BurnieCoinflip.sol should be checked for the inverse (any references to BurnieCoin state that moved or changed). |
| Phase 29 peripheral NatSpec | git show 9238faf2:audit/v3.0-doc-peripheral-natspec.md | Phase 29 verified all peripheral contract functions as MATCH at function-level NatSpec. v3.1 applies deeper scrutiny. |
| KNOWN-ISSUES.md | audit/KNOWN-ISSUES.md | Design decisions documented for wardens |

## Architecture Patterns

### Contract File Inventory (by size, for work ordering)

```
contracts/DegenerusQuests.sol          1,598 lines  (249 NatSpec tags, ~558 comment lines, 35 functions) [NO POST-PHASE-29 CHANGES]
contracts/BurnieCoinflip.sol           1,154 lines  (62 NatSpec tags, ~152 comment lines, 37 functions)  [NO POST-PHASE-29 CHANGES]
contracts/DegenerusVault.sol           1,061 lines  (287 NatSpec tags, ~368 comment lines, 82 functions) [NO POST-PHASE-29 CHANGES]
contracts/DegenerusAffiliate.sol         847 lines  (128 NatSpec tags, ~337 comment lines, 22 functions) [NO POST-PHASE-29 CHANGES]
contracts/DegenerusJackpots.sol          689 lines  (78 NatSpec tags, ~128 comment lines, 14 functions)  [NO POST-PHASE-29 CHANGES]
contracts/DegenerusDeityPass.sol         392 lines  (13 NatSpec tags, ~40 comment lines, 31 functions)   [NO POST-PHASE-29 CHANGES]
contracts/Icons32Data.sol                228 lines  (48 NatSpec tags, ~70 comment lines, 5 functions)    [NO POST-PHASE-29 CHANGES]
contracts/DegenerusTraitUtils.sol        183 lines  (17 NatSpec tags, ~53 comment lines, 3 functions)    [NO POST-PHASE-29 CHANGES]
contracts/DeityBoonViewer.sol            171 lines  (8 NatSpec tags, ~13 comment lines, 3 functions)     [NO POST-PHASE-29 CHANGES]
contracts/ContractAddresses.sol           39 lines  (0 NatSpec tags, ~4 comment lines, 0 functions)      [NO POST-PHASE-29 CHANGES]
                                       -----
Total:                                 6,362 lines  (890 NatSpec tags, ~1,723 comment lines, 232 functions)
```

### Peripheral Contract Dependency Structure

```
BurnieCoinflip.sol (COINFLIP)
  - Extracted from BurnieCoin -- manages daily coinflip wagering system
  - References: BURNIE (BurnieCoin), GAME, QUESTS, JACKPOTS, WWXRP via direct interfaces
  - Key patterns: deposit/claim/auto-rebuy, bounty system, BAF leaderboard recording,
    afKing recycling bonuses, quest integration, RNG processing

DegenerusAffiliate.sol (AFFILIATE)
  - Multi-tier referral system with configurable kickback
  - References: COIN (BurnieCoin), GAME via ContractAddresses
  - Key patterns: 3-tier referral (base/upline1/upline2), kickback, leaderboard,
    lootbox activity taper, per-referrer commission cap

DegenerusDeityPass.sol (DEITY_PASS)
  - Soulbound ERC721 for deity passes. 32 tokens max.
  - References: GAME, ICONS_32 via ContractAddresses
  - Key patterns: soulbound (all transfers revert), on-chain SVG rendering,
    optional external renderer with fallback

DegenerusQuests.sol (QUESTS)
  - Daily quest system with 2 rotating slots and streak tracking
  - References: GAME, COIN, COINFLIP via ContractAddresses
  - Key patterns: quest rolling from VRF entropy, 9 quest types, progress versioning,
    streak shields, per-slot completion tracking

DegenerusJackpots.sol (JACKPOTS)
  - BAF jackpot system with leaderboard-based distribution
  - References: COINFLIP (for coinflipTopLastDay view), GAME via ContractAddresses
  - Key patterns: BAF flip recording, epoch-based lazy reset, scatter rounds,
    multi-winner distribution

DegenerusVault.sol (VAULT)
  - Multi-asset vault with 2 independent share classes (DGVB, DGVE)
  - References: GAME, COIN, COINFLIP, STETH, WWXRP via ContractAddresses
  - Key patterns: virtual BURNIE deposit (mint allowance escrow), proportional claims,
    share refill mechanism, vault-owner gameplay proxying
  - SPECIAL: Contains embedded DegenerusVaultShare contract (minimal ERC20)

DegenerusTraitUtils.sol (library)
  - Pure utility library for deterministic trait generation
  - No external references -- pure functions only
  - Key patterns: weighted bucket distribution, trait packing from 256-bit seeds

DeityBoonViewer.sol (view contract)
  - Standalone view for computing deity boon slot types
  - References: DegenerusGame via interface parameter (not ContractAddresses)
  - Key patterns: weighted random boon selection, decimator/deity eligibility gating

ContractAddresses.sol (library)
  - Compile-time constants for all contract addresses
  - Zero-address placeholders replaced by deploy script
  - No functions, no NatSpec -- 4 comment lines only

Icons32Data.sol (data contract)
  - On-chain SVG icon path storage for Degenerus symbols
  - References: CREATOR via ContractAddresses
  - Key patterns: batch initialization, finalization lock, quadrant-indexed symbol names
```

### Post-Phase-29 Code Changes (Critical Context)

| Contract | Commit | Changes | Impact on Comments |
|----------|--------|---------|--------------------|
| BurnieCoinflip.sol | (none) | No changes since Phase 29. | Full re-review with v3.1 warden-readability lens. |
| DegenerusAffiliate.sol | (none) | No changes since Phase 29. | Full re-review. |
| DegenerusDeityPass.sol | (none) | No changes since Phase 29. | Full re-review. |
| DegenerusQuests.sol | (none) | No changes since Phase 29. | Full re-review. |
| DegenerusJackpots.sol | (none) | No changes since Phase 29. | Full re-review. |
| DegenerusVault.sol | (none) | No changes since Phase 29. | Full re-review. |
| DegenerusTraitUtils.sol | (none) | No changes since Phase 29. | Full re-review. |
| DeityBoonViewer.sol | (none) | No changes since Phase 29. | Full re-review. |
| ContractAddresses.sol | (none) | No changes since Phase 29. | Full re-review. |
| Icons32Data.sol | (none) | No changes since Phase 29. | Full re-review. |

### Pre-Identified Issues (from research read-through)

**BurnieCoinflip.sol:**

1. **Error reuse in _resolvePlayer (line 1142):** The `_resolvePlayer` helper reverts with `OnlyBurnieCoin()` when operator approval fails (line 1142). The comment says `// Reusing error` but this is misleading -- `OnlyBurnieCoin` is an access control error for the `onlyBurnieCoin` modifier (lines 203-206). A warden seeing `revert OnlyBurnieCoin()` from a player-facing function would investigate whether an unauthorized BurnieCoin call is occurring, when actually the revert means "you are not approved to act on behalf of this player." This mirrors the `OnlyGame()` error reuse pattern found in BurnieCoin.sol (CMT-043).

2. **depositCoinflip missing NatSpec for access control pattern (line 225):** The `depositCoinflip` function has only `/// @notice Deposit BURNIE into daily coinflip system.` -- it lacks @dev/@param/@return tags. The function has complex access control (self-deposit vs. operator-approved deposit) that wardens need to understand.

3. **`coin` constant references COINFLIP address but NatSpec says "coin contract" (DegenerusJackpots.sol line 93):** The `IDegenerusCoinJackpotView internal constant coin` is set to `ContractAddresses.COINFLIP` but the NatSpec says "Coinflip contract for coinflip stats queries" -- this is correct in NatSpec but the variable name `coin` is misleading. Need to verify the NatSpec description is accurate even though the naming is confusing.

**DegenerusDeityPass.sol:**

4. **Very sparse NatSpec coverage:** Only 13 NatSpec tags for 31 functions. Most functions have zero NatSpec (no @notice, @dev, @param, @return). Functions like `balanceOf`, `ownerOf`, `getApproved`, `isApprovedForAll`, `approve`, `setApprovalForAll`, `transferFrom`, `safeTransferFrom`, `_renderSvgInternal`, `_tryRenderExternal`, `_isHexColor`, `_symbolFitScale`, `_symbolTranslate`, `_mat6`, `_dec6`, `_dec6s`, `_pad6`, `supportsInterface` -- all have no NatSpec. Whether these need flagging depends on whether the behavior is obvious from the function signature alone. ERC721 standard functions (balanceOf, ownerOf, etc.) have well-known semantics and may not need NatSpec. Internal rendering helpers (_renderSvgInternal, _mat6, _pad6) are implementation details. But `mint` at line 381 has NatSpec, which is appropriate given it is the only non-standard function. Evaluate on a function-by-function basis.

**DegenerusQuests.sol:**

5. **QUEST_TYPE_RESERVED = 4 (line 153):** Marked as "Retired quest type id kept reserved for compatibility." This constant is never used in the contract code -- it exists only to reserve the ID value. This is potentially an intent drift item (vestigial reservation from a removed quest type) or a deliberate defensive measure. Need to verify whether any code references QUEST_TYPE_RESERVED.

6. **onlyCoin modifier allows COINFLIP (line 284-288):** The `onlyCoin` modifier checks for both `ContractAddresses.COIN` and `ContractAddresses.COINFLIP`. The modifier name `onlyCoin` is misleading since COINFLIP is also allowed. The @dev says "Restricts access to the authorized COIN or COINFLIP contract" which is accurate, but the modifier name itself is confusing. Need to evaluate whether this is a CMT finding.

**DegenerusVault.sol:**

7. **Dual-contract file:** DegenerusVault.sol contains two contracts: `DegenerusVaultShare` (lines 139-301) and `DegenerusVault` (lines 310-1061). The share contract is a minimal ERC20. Both need separate review for NatSpec completeness, but both are well-documented from initial reading.

8. **DegenerusJackpots.sol section header (lines 162-166):** The "COIN CONTRACT HOOKS" section header says "Called by BurnieCoin to record coinflip activity." But the `onlyCoin` modifier allows both COIN and COINFLIP. `recordBafFlip` is called by BurnieCoinflip (COINFLIP), not BurnieCoin (COIN). Need to verify which contract actually calls this.

### Recommended Plan Split

Based on contract sizes, logical groupings, and balanced workload:

**Plan 1 (Wave 1): BurnieCoinflip.sol (1,154 lines)**
- Largest peripheral with the coinflip split history
- 62 NatSpec tags, 37 functions
- Error reuse pattern, sparse NatSpec on key functions
- Creates the batch findings file with header
- ~1,154 lines review

**Plan 2 (Wave 1): DegenerusQuests.sol + DegenerusJackpots.sol (2,287 lines combined)**
- DegenerusQuests.sol: 1,598 lines, 249 NatSpec tags, 35 functions -- densest NatSpec in the batch
- DegenerusJackpots.sol: 689 lines, 78 NatSpec tags, 14 functions -- BAF leaderboard/distribution system
- Both are game mechanics peripherals that interact with coinflip
- ~2,287 lines review

**Plan 3 (Wave 1): DegenerusAffiliate.sol + DegenerusVault.sol (1,908 lines combined)**
- DegenerusAffiliate.sol: 847 lines, 128 NatSpec tags, 22 functions -- referral system
- DegenerusVault.sol: 1,061 lines, 287 NatSpec tags, 82 functions -- vault + share token (2 contracts)
- Both are reward/economic peripherals
- ~1,908 lines review

**Plan 4 (Wave 1): DegenerusDeityPass.sol + DegenerusTraitUtils.sol + DeityBoonViewer.sol + ContractAddresses.sol + Icons32Data.sol + Finalize (1,013 lines combined)**
- DegenerusDeityPass.sol: 392 lines, 13 NatSpec tags, 31 functions -- minimal NatSpec (may flag)
- DegenerusTraitUtils.sol: 183 lines, 17 NatSpec tags, 3 functions -- pure library
- DeityBoonViewer.sol: 171 lines, 8 NatSpec tags, 3 functions -- view-only
- ContractAddresses.sol: 39 lines, 0 NatSpec tags, 0 functions -- constants library
- Icons32Data.sol: 228 lines, 48 NatSpec tags, 5 functions -- data contract
- Finalize: update summary counts, cross-check numbering
- ~1,013 lines review

### Finding Numbering Continuation

Phase 31 ended at: CMT-010, DRIFT-002
Phase 32 ended at: CMT-024, DRIFT-002 (no new DRIFT)
Phase 33 ended at: CMT-040, DRIFT-003
Phase 34 ended at: CMT-058, DRIFT-003 (no new DRIFT)
Phase 35 starts at: CMT-059, DRIFT-004

### Findings File Format

```markdown
# Phase 35 Findings: Peripheral Contracts

**Date:** 2026-03-19
**Scope:** BurnieCoinflip, DegenerusAffiliate, DegenerusDeityPass, DegenerusQuests, DegenerusJackpots, DegenerusVault, DegenerusTraitUtils, DeityBoonViewer, ContractAddresses, Icons32Data
**Pass:** v3.1 second independent review (v3.0 Phase 29 was first pass)
**Mode:** Flag-only -- no code changes

## Summary

| Contract | CMT findings | DRIFT findings | Total |
|----------|-------------|----------------|-------|
| BurnieCoinflip.sol | X | Y | Z |
| DegenerusQuests.sol | X | Y | Z |
| DegenerusJackpots.sol | X | Y | Z |
| DegenerusAffiliate.sol | X | Y | Z |
| DegenerusVault.sol | X | Y | Z |
| DegenerusDeityPass.sol | X | Y | Z |
| DegenerusTraitUtils.sol | X | Y | Z |
| DeityBoonViewer.sol | X | Y | Z |
| ContractAddresses.sol | X | Y | Z |
| Icons32Data.sol | X | Y | Z |
| **Total** | **X** | **Y** | **Z** |

*Summary counts updated after all contracts reviewed.*
```

### Verification Methodology for v3.1

Same methodology as Phases 31-34, adapted for peripheral contracts:

**CMT-05 approach (comment accuracy):**
1. For each contract, read every NatSpec tag (@notice, @dev, @param, @return, @custom) and every inline // comment
2. For each comment, verify it matches actual code behavior in the current HEAD
3. Focus on warden-readability: "Would a C4A warden reading this be misled?"
4. Flag any mismatch as a finding with what/why/suggestion
5. Pay special attention to BurnieCoinflip.sol cross-references to BurnieCoin (coinflip split artifacts)
6. Pay attention to DegenerusDeityPass.sol sparse NatSpec -- flag only where absence is misleading
7. DegenerusVault.sol contains 2 contracts (DegenerusVaultShare + DegenerusVault) -- review both
8. ContractAddresses.sol has 0 NatSpec and 0 functions -- verify the 4 comment lines only

**DRIFT-05 approach (intent drift):**
1. Scan BurnieCoinflip.sol for error reuse pattern and any vestigial references from the coinflip split
2. Check DegenerusQuests.sol QUEST_TYPE_RESERVED for vestigial/deliberate status
3. Check DegenerusJackpots.sol "COIN CONTRACT HOOKS" section header accuracy (COINFLIP calls these, not COIN)
4. Check DegenerusAffiliate.sol for any access control NatSpec that doesn't match actual callers
5. Check DegenerusVault.sol for any stale references to removed features
6. Check DegenerusDeityPass.sol for any unnecessary guards
7. Flag any vestigial logic with what/why/suggestion

### Anti-Patterns to Avoid

- **Rubber-stamping Phase 29 verdicts:** Phase 29 verified function-level NatSpec (DOC-01) and inline comments (DOC-02). It did NOT check block comments, section headers, error reuse patterns, or cross-contract reference accuracy.
- **Flagging standard ERC721 functions for missing NatSpec:** DegenerusDeityPass.sol has 31 functions but only 13 NatSpec tags. Many undocumented functions are standard ERC721 (balanceOf, ownerOf, transferFrom, safeTransferFrom, approve, setApprovalForAll, supportsInterface). These have well-known semantics. Only flag if the implementation deviates from the standard in a way that wardens would need documentation to understand (e.g., the soulbound revert pattern IS documented via `Soulbound()` error).
- **Flagging private rendering helpers for missing NatSpec:** DegenerusDeityPass.sol has private SVG rendering helpers (_renderSvgInternal, _mat6, _pad6, _dec6, _dec6s) that are implementation details. These are not warden-relevant unless a warden would audit the SVG generation for injection vulnerabilities.
- **Treating ContractAddresses.sol as needing NatSpec:** It is a compile-time constants library with zero addresses in source, populated by the deploy script. The 4 comment lines explain this. No NatSpec is expected or useful.
- **Scope creep into code fixes:** If a real bug or optimization is found, document it as a finding but do NOT attempt code changes. This is flag-only.
- **Confusing `coin` variable name with COIN address in DegenerusJackpots.sol:** The `coin` variable at line 93 points to `ContractAddresses.COINFLIP` (the coinflip contract). The NatSpec correctly says "Coinflip contract" but the variable name is confusing. This is a naming issue, not a code bug. Evaluate whether to flag as CMT (misleading variable name in NatSpec context) or not.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Finding post-Phase-29 changes | Manual git log | `git log 9238faf2..HEAD -- contracts/File.sol` | Precise identification of what changed |
| Counting NatSpec tags | Manual counting | `grep -cE '@dev\|@notice\|@param\|@return' contracts/File.sol` | Accurate enumeration |
| Verifying error reuse | Reading all error uses manually | `grep -n 'revert OnlyBurnieCoin' contracts/BurnieCoinflip.sol` | Quick identification of all revert sites |
| Checking QUEST_TYPE_RESERVED usage | Manual scanning | `grep -n 'QUEST_TYPE_RESERVED\|= 4' contracts/DegenerusQuests.sol` | Confirms whether constant is used |
| Cross-referencing BurnieCoin/BurnieCoinflip | Manual comparison | Phase 34 findings file as reference for known coinflip split artifacts | Avoid re-discovering already-flagged issues |

## Common Pitfalls

### Pitfall 1: BurnieCoinflip Error Reuse Pattern
**What goes wrong:** BurnieCoinflip.sol reuses `OnlyBurnieCoin()` error in `_resolvePlayer` (line 1142) for operator approval failures. This mirrors the `OnlyGame()` error reuse pattern found in BurnieCoin.sol (CMT-043).
**Why it happens:** Gas optimization -- fewer error definitions means smaller bytecode.
**How to avoid:** Flag the reuse with an inline comment suggestion matching the Phase 34 pattern (CMT-043). The comment at line 1142 says `// Reusing error` which is a partial acknowledgment but doesn't explain what the error is being reused for.
**Warning signs:** A warden seeing `revert OnlyBurnieCoin()` in a function called by any address would investigate whether BurnieCoin is supposed to be the caller.

### Pitfall 2: DegenerusDeityPass Sparse NatSpec
**What goes wrong:** DegenerusDeityPass.sol has only 13 NatSpec tags for 31 functions. A reviewer might flag every missing NatSpec as a finding, creating noise.
**Why it happens:** The contract is largely standard ERC721 with soulbound restrictions. Standard functions have well-known behavior.
**How to avoid:** Only flag missing NatSpec where the behavior would surprise a warden. Standard ERC721 functions (balanceOf, ownerOf, etc.) and internal rendering helpers don't need NatSpec flags. Focus on non-obvious behavior: the soulbound enforcement pattern IS clear from the Soulbound() error. The `mint` function HAS NatSpec (appropriate for the only non-standard entry point).
**Warning signs:** More than 10 findings from DegenerusDeityPass.sol is likely noise.

### Pitfall 3: DegenerusJackpots.sol COIN vs COINFLIP Confusion
**What goes wrong:** DegenerusJackpots.sol has a `coin` variable that points to `ContractAddresses.COINFLIP`. The section header says "Called by BurnieCoin" but the actual caller is BurnieCoinflip.
**Why it happens:** When BurnieCoinflip was split from BurnieCoin, the jackpots contract's `coin` reference was updated to point to COINFLIP, but naming and section headers may not have been updated.
**How to avoid:** Verify which contract actually calls `recordBafFlip`. Check the `onlyCoin` modifier to see if it allows COIN, COINFLIP, or both. Trace the call path from the coinflip deposit flow.
**Warning signs:** Section headers referencing "BurnieCoin" when the actual caller is "BurnieCoinflip."

### Pitfall 4: DegenerusVault.sol Dual-Contract File
**What goes wrong:** DegenerusVault.sol contains two contracts. A reviewer might accidentally skip DegenerusVaultShare (lines 139-301) or treat it as part of the DegenerusVault contract.
**Why it happens:** DegenerusVaultShare is a minimal ERC20 embedded in the same file. It has its own NatSpec, events, errors, and functions.
**How to avoid:** Review DegenerusVaultShare and DegenerusVault as separate contracts with separate finding counts. The summary table should list "DegenerusVault.sol" as one entry covering both contracts.
**Warning signs:** Missing coverage of DegenerusVaultShare functions.

### Pitfall 5: DegenerusQuests.sol Dense NatSpec
**What goes wrong:** DegenerusQuests.sol has 249 NatSpec tags -- the highest density in the batch. A reviewer might skim and miss subtle inaccuracies.
**Why it happens:** The quest system is complex with 9 quest types, 2 slots, streak tracking, shields, and progress versioning. Heavy documentation is appropriate but creates a large verification surface.
**How to avoid:** Systematic verification: constants section, then structs, then modifiers, then each handler function. The handler functions follow a consistent pattern (early-exit, sync state, find matching slot, accumulate progress, check completion). Verify the pattern documentation matches reality.
**Warning signs:** Spending less than 20% of review time on DegenerusQuests.sol despite it being 25% of the line count.

## Code Examples

### Verifying No Post-Phase-29 Changes (all 10 contracts)

```bash
# Confirm ALL 10 contracts unchanged since Phase 29
git log 9238faf2..HEAD -- \
  contracts/BurnieCoinflip.sol \
  contracts/DegenerusAffiliate.sol \
  contracts/DegenerusDeityPass.sol \
  contracts/DegenerusQuests.sol \
  contracts/DegenerusJackpots.sol \
  contracts/DegenerusVault.sol \
  contracts/DegenerusTraitUtils.sol \
  contracts/DeityBoonViewer.sol \
  contracts/ContractAddresses.sol \
  contracts/Icons32Data.sol
# (should be empty -- verified during research)
```

### Verifying BurnieCoinflip Error Reuse

```bash
# Find all revert sites in BurnieCoinflip.sol
grep -n 'revert Only' contracts/BurnieCoinflip.sol
# Expected: OnlyDegenerusGame, OnlyFlipCreditors, OnlyBurnieCoin at appropriate modifiers
# Plus OnlyBurnieCoin at line 1142 in _resolvePlayer (error reuse)
```

### Verifying QUEST_TYPE_RESERVED Usage

```bash
grep -n 'QUEST_TYPE_RESERVED' contracts/DegenerusQuests.sol
# Expected: only the constant declaration at line 153, no actual usage in code logic
```

### Verifying DegenerusJackpots `coin` Reference

```bash
grep -n 'coin\.' contracts/DegenerusJackpots.sol
# Expected: coin.coinflipTopLastDay() -- confirms coin variable calls into coinflip contract
```

## State of the Art

This section is not applicable to a documentation verification phase. No libraries, frameworks, or evolving standards are involved. The Solidity 0.8.34 compiler and NatSpec specification are stable.

## Open Questions

1. **DegenerusDeityPass NatSpec sparsity: flag or not?**
   - What we know: 13 NatSpec tags for 31 functions. Many functions are standard ERC721 that have well-known semantics. The soulbound pattern is self-documenting via `Soulbound()` error.
   - What's unclear: Should undocumented ERC721 standard functions be flagged? Phase 34 did not flag undocumented standard ERC20 functions in DegenerusStonk.sol (which has 41 NatSpec for 14 functions -- higher density).
   - Recommendation: Do NOT flag standard ERC721 functions (balanceOf, ownerOf, getApproved, isApprovedForAll, approve, setApprovalForAll, transferFrom, safeTransferFrom, supportsInterface) or private rendering helpers. Flag only if implementation deviates from standard in an undocumented way.

2. **DegenerusQuests.sol QUEST_TYPE_RESERVED -- intent drift or deliberate?**
   - What we know: `QUEST_TYPE_RESERVED = 4` is declared and marked as "Retired quest type id kept reserved for compatibility." It is never used in code logic.
   - What's unclear: Whether the reservation is vestigial (leftover from a removed feature) or deliberate (preventing a future implementation from accidentally reusing ID 4 and breaking event parsing).
   - Recommendation: Flag as INFO-level DRIFT if the constant is truly unused. The "reserved for compatibility" comment suggests it is deliberate defensive code, but the original quest type it replaced is unknown. A warden might wonder what quest type 4 was.

3. **DegenerusJackpots.sol section header accuracy: "Called by BurnieCoin" vs COINFLIP**
   - What we know: The "COIN CONTRACT HOOKS" section says "Called by BurnieCoin to record coinflip activity." The `onlyCoin` modifier allows both COIN and COINFLIP. The `recordBafFlip` function is likely called by BurnieCoinflip (COINFLIP) during coinflip deposits.
   - What's unclear: Whether BurnieCoin also calls `recordBafFlip` or if the section header is vestigial from before the coinflip split.
   - Recommendation: Verify during audit by tracing the call path. If only COINFLIP calls `recordBafFlip`, the section header is stale and should be flagged.

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
| CMT-05 | NatSpec and inline comments in 10 peripheral contracts are accurate and warden-ready | manual-only | N/A -- requires reading and cross-referencing each comment against code | N/A |
| DRIFT-05 | Peripheral contracts reviewed for vestigial logic, unnecessary restrictions, and intent drift | manual-only | N/A -- requires understanding designer intent vs actual behavior | N/A |

**Justification for manual-only:** This phase verifies the semantic accuracy of human-written English comments against code behavior and design intent. There is no automated tool that can determine whether a NatSpec description would mislead a C4A warden. The verification requires understanding cross-contract interactions, the coinflip split history, quest type semantics, and the protocol's intended design.

### Sampling Rate
- **Per task commit:** Review findings file for completeness -- every function and block comment in the target contract(s) should be covered
- **Per wave merge:** Cross-check that all 10 contracts are covered with no files missed
- **Phase gate:** CMT-05 and DRIFT-05 both have explicit verdicts; a per-batch findings file exists with what/why/suggestion for every item

### Wave 0 Gaps
None -- no test infrastructure needed. This is a documentation/findings-only audit phase producing a findings markdown file.

## Sources

### Primary (HIGH confidence)
- contracts/BurnieCoinflip.sol -- 1,154 lines, read in full during research. Error reuse pattern at line 1142 identified. Sparse NatSpec on depositCoinflip (line 225).
- contracts/DegenerusAffiliate.sol -- 847 lines, read partially during research (first 480 lines). Well-documented with dense NatSpec including reward flow diagrams.
- contracts/DegenerusDeityPass.sol -- 392 lines, read in full during research. Sparse NatSpec (13 tags for 31 functions). Standard ERC721 with soulbound enforcement.
- contracts/DegenerusQuests.sol -- 1,598 lines, read partially (first 480 lines). Dense NatSpec (249 tags). QUEST_TYPE_RESERVED = 4 identified as potential vestigial item.
- contracts/DegenerusJackpots.sol -- 689 lines, read partially (first 280 lines). Section header "COIN CONTRACT HOOKS" references BurnieCoin but caller is likely BurnieCoinflip.
- contracts/DegenerusVault.sol -- 1,061 lines, read partially (first 570 lines). Dual-contract file (DegenerusVaultShare + DegenerusVault). Well-documented.
- contracts/DegenerusTraitUtils.sol -- 183 lines, read in full. Comprehensive block comments and NatSpec. Pure library.
- contracts/DeityBoonViewer.sol -- 171 lines, read in full. Minimal NatSpec (8 tags for 3 functions). _boonFromRoll has no NatSpec.
- contracts/ContractAddresses.sol -- 39 lines, read in full. Zero NatSpec, 4 comment lines explaining deploy script pattern.
- contracts/Icons32Data.sol -- 228 lines, read in full. Comprehensive block comments and NatSpec (48 tags).
- git log 9238faf2..HEAD -- verified 0 contracts changed in this batch.
- audit/v3.1-findings-34-token-contracts.md -- Phase 34 findings endpoint: CMT-058, DRIFT-003. Phase 35 starts at CMT-059, DRIFT-004.

### Secondary (MEDIUM confidence)
- .planning/STATE.md -- Accumulated context from Phases 31-34 (coinflip split orphaned NatSpec patterns, error reuse patterns).

## Metadata

**Confidence breakdown:**
- Scope assessment: HIGH -- all 10 contract files read (in full or partially), line/NatSpec/function counts verified via grep and wc, post-Phase-29 changes confirmed absent via git log
- Pre-identified issues: HIGH -- error reuse pattern in BurnieCoinflip.sol confirmed, sparse NatSpec in DegenerusDeityPass.sol confirmed, section header concern in DegenerusJackpots.sol identified
- Methodology: HIGH -- standard NatSpec/inline review approach proven in Phases 31-34, reusing established findings format
- Plan structure: HIGH -- 4-plan split balances workload (1,154 / 2,287 / 1,908 / 1,013 lines per plan)
- Completeness of pre-identified issues: MEDIUM -- 8 pre-identified issues are verified, but full review of 890 NatSpec tags and ~1,723 comment lines may surface additional findings (this batch is 3x larger than any prior batch)

**Research date:** 2026-03-19
**Valid until:** 2026-04-18 (30 days -- stable domain, contracts not expected to change during audit prep)
