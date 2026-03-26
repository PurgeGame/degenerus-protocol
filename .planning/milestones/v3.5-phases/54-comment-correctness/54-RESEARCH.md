# Phase 54: Comment Correctness - Research

**Researched:** 2026-03-21
**Domain:** Solidity NatSpec and inline comment verification across all protocol contracts
**Confidence:** HIGH

## Summary

Phase 54 is the FINAL comment correctness sweep before C4A submission. This is the third full comment pass (after v3.1 Phase 29/31-35 and v3.2 Phases 39-41), but the first since v3.3 gambling burn changes, v3.4 skim redesign and redemption lootbox additions, and the `fba43f2c` bulk fix commit that resolved most outstanding v3.2 findings. The scope is 46 Solidity files totaling ~27,873 lines across 5 categories: 16 core contracts, 12 interfaces, 5 libraries, 12 modules, and 1 storage contract.

Prior comment audits found 84 findings in v3.1 (80 CMT + 4 DRIFT) and 30 in v3.2 (6 LOW + 24 INFO). Of the v3.2 findings, the `fba43f2c` commit resolved the remaining 4 that were not already fixed in prior milestones (CMT-003, CMT-201, INFO-01, OQ-1). However, the fix commit itself modified 7 contract files, and v3.3/v3.4 modified additional contracts. These code changes are the PRIMARY source of potential new comment drift. Additionally, some v3.2 findings may have been intentionally deferred (e.g., cosmetic INFO items marked "accept as known"). This phase must verify the current state of ALL comments, not just the previously-flagged ones.

The deliverable is a findings document per batch of contracts, using the established finding format (ID, severity, contract, line ref, description, recommendation). The output feeds directly into Phase 58 (Consolidated Findings).

**Primary recommendation:** Split into 6 plans organized by contract domain and file size. Prioritize contracts modified since v3.2 (highest drift risk). The focus should be on: (1) new NatSpec added during v3.3/v3.4 code changes, (2) stale comments that reference pre-gambling-burn or pre-skim-redesign behavior, (3) interface/implementation NatSpec consistency, and (4) the handful of v3.2 findings that may still be open.

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| CMT-01 | Every NatSpec tag (@param, @return, @dev, @notice) across all 34 contracts matches current code behavior | 46 .sol files (including interfaces, libraries). Prior passes found that NatSpec tags commonly drift when code is changed but comments are not updated -- v3.2 Pattern 1 (stale NatSpec after code removal) had 7 findings. Contracts modified in v3.3/v3.4 are highest risk: StakedDegenerusStonk, DegenerusStonk, BurnieCoinflip, AdvanceModule, LootboxModule, DegenerusGame, BurnieCoin, DegenerusAdmin, GameStorage, DegenerusVault. |
| CMT-02 | No stale references to removed features, renamed variables, or changed semantics | v3.3 removed rngLocked from claim paths, added gambling burn/redemption system. v3.4 redesigned skim pipeline and added redemption lootbox. v3.2 Pattern 1 showed 7 stale-reference findings from prior removals. IBurnieCoinflip still has 2 `@custom:reverts RngLocked` annotations on setCoinflipAutoRebuy/setCoinflipAutoRebuyTakeProfit that ARE legitimate (implementation still checks). The v3.2 LOW-01/02/03 (stale RngLocked on claim functions) were fixed in v3.3. |
| CMT-03 | Inline comments accurately describe the code they annotate | v3.2 Pattern 4 found interface/header comments stale after refactoring. v3.4 F-50-01 and F-50-02 were INFO findings about NatSpec not matching bit-field consumption patterns in AdvanceModule -- these were resolved in `fba43f2c`. Inline comments on new skim pipeline code and redemption lootbox code need fresh verification. |
| CMT-04 | All findings documented with contract, line ref, and fix recommendation | Established format from v3.1/v3.2: finding ID (CMT-V35-NNN or similar), severity (LOW/INFO), contract name, line number, description, recommendation. Output as markdown findings files in `audit/` directory, organized by batch. |
</phase_requirements>

## Standard Stack

This phase uses no external libraries or tools. It is a manual audit task.

### Core
| Tool | Purpose | Why Standard |
|------|---------|--------------|
| Solidity source files (contracts/) | Primary verification target | Source of truth per project memory |
| Prior findings (audit/v3.1-findings-consolidated.md) | Historical finding patterns | 84 findings with established numbering |
| Prior findings (audit/v3.2-findings-consolidated.md) | Current open items reference | 30 findings, most now fixed |
| Prior findings (audit/v3.4-findings-consolidated.md) | Recent comment-relevant findings | F-50-01, F-50-02 were comment findings |
| PAYOUT-SPECIFICATION.html | Fund routing ground truth | Validates NatSpec claims about ETH/token flows |
| KNOWN-ISSUES.md | Design decisions for wardens | Avoids flagging intentional design |

### Ground Truth Sources (for cross-reference)
| Source | What It Proves |
|--------|---------------|
| audit/v1.1-ECONOMICS-PRIMER.md | Economic model overview |
| audit/v1.1-parameter-reference.md | Named constant values |
| v3.3/v3.4 audit deliverables | Recent code change verification |

## Architecture Patterns

### Full Contract Inventory (46 files, ~27,873 lines)

**Core Contracts (16 files, ~14,285 lines):**
```
contracts/DegenerusGame.sol               2,919 lines  [MODIFIED v3.3/v3.4/fix]
contracts/BurnieCoinflip.sol              1,129 lines  [MODIFIED v3.3]
contracts/DegenerusQuests.sol             1,598 lines
contracts/BurnieCoin.sol                  1,075 lines  [MODIFIED fix]
contracts/DegenerusVault.sol              1,050 lines  [MODIFIED fix]
contracts/DegenerusAffiliate.sol            840 lines
contracts/StakedDegenerusStonk.sol          837 lines  [MODIFIED v3.3/v3.4/fix]
contracts/DegenerusAdmin.sol                804 lines  [MODIFIED fix]
contracts/DegenerusJackpots.sol             689 lines
contracts/DegenerusDeityPass.sol            392 lines
contracts/WrappedWrappedXRP.sol             389 lines
contracts/DegenerusStonk.sol                249 lines  [MODIFIED v3.3]
contracts/Icons32Data.sol                   228 lines
contracts/DegenerusTraitUtils.sol           183 lines
contracts/DeityBoonViewer.sol               171 lines
contracts/ContractAddresses.sol              38 lines
```

**Modules (12 files, ~9,915 lines):**
```
contracts/modules/DegenerusGameJackpotModule.sol       2,795 lines
contracts/modules/DegenerusGameLootboxModule.sol       1,814 lines  [MODIFIED v3.4]
contracts/modules/DegenerusGameAdvanceModule.sol       1,453 lines  [MODIFIED v3.4/fix]
contracts/modules/DegenerusGameMintModule.sol          1,199 lines
contracts/modules/DegenerusGameDegeneretteModule.sol   1,179 lines
contracts/modules/DegenerusGameDecimatorModule.sol     1,024 lines
contracts/modules/DegenerusGameWhaleModule.sol           840 lines
contracts/modules/DegenerusGameEndgameModule.sol         540 lines
contracts/modules/DegenerusGameBoonModule.sol            359 lines
contracts/modules/DegenerusGameGameOverModule.sol        235 lines
contracts/modules/DegenerusGamePayoutUtils.sol            94 lines
contracts/modules/DegenerusGameMintStreakUtils.sol         62 lines
```

**Interfaces (12 files, ~1,399 lines):**
```
contracts/interfaces/IDegenerusGame.sol                   459 lines
contracts/interfaces/IDegenerusGameModules.sol             419 lines
contracts/interfaces/IBurnieCoinflip.sol                   186 lines  [MODIFIED v3.3]
contracts/interfaces/IDegenerusQuests.sol                  150 lines
contracts/interfaces/IStakedDegenerusStonk.sol              93 lines
contracts/interfaces/IDegenerusAffiliate.sol                 62 lines
contracts/interfaces/IVRFCoordinator.sol                    46 lines
contracts/interfaces/IDegenerusCoin.sol                     41 lines
contracts/interfaces/IStETH.sol                             36 lines
contracts/interfaces/IDegenerusJackpots.sol                 33 lines
contracts/interfaces/DegenerusGameModuleInterfaces.sol      32 lines
contracts/interfaces/IVaultCoin.sol                         31 lines
```

**Libraries (5 files, ~501 lines):**
```
contracts/libraries/JackpotBucketLib.sol     307 lines
contracts/libraries/BitPackingLib.sol         88 lines
contracts/libraries/PriceLookupLib.sol        47 lines
contracts/libraries/GameTimeLib.sol           35 lines
contracts/libraries/EntropyLib.sol            24 lines
```

**Storage (1 file, ~1,599 lines):**
```
contracts/storage/DegenerusGameStorage.sol  1,599 lines  [MODIFIED fix]
```

### Contracts Modified Since v3.2 (Highest Drift Risk)

These contracts have been changed after the last full comment audit (v3.2). They are the primary targets for new comment drift:

| Contract | Modified In | Change Description | Risk Level |
|----------|-------------|-------------------|------------|
| StakedDegenerusStonk.sol | v3.3 + v3.4 + fix | Gambling burn, redemption lootbox, NatSpec fixes | HIGH |
| DegenerusGame.sol | v3.3 + v3.4 + fix | Redemption resolution, lootbox routing, module delegation, NatSpec fixes | HIGH |
| DegenerusGameAdvanceModule.sol | v3.4 + fix | Skim pipeline redesign, bit allocation NatSpec fixes | HIGH |
| DegenerusGameLootboxModule.sol | v3.4 | Redemption lootbox 50/50 split routing | HIGH |
| BurnieCoinflip.sol | v3.3 | Gambling burn claim paths, error renames | MEDIUM |
| DegenerusStonk.sol | v3.3 | gameOver guard on burn | MEDIUM |
| IBurnieCoinflip.sol | v3.3 | NatSpec updates for new functions | MEDIUM |
| BurnieCoin.sol | fix | balanceOfWithClaimable NatSpec | LOW |
| DegenerusAdmin.sol | fix | lastVrfProcessedTimestamp NatSpec | LOW |
| DegenerusVault.sol | fix | _transfer @dev singular fix | LOW |
| DegenerusGameStorage.sol | fix | Slot boundary comment | LOW |
| IDegenerusGameModules.sol | v3.4 | New module interface functions | MEDIUM |
| IStakedDegenerusStonk.sol | v3.3 | New redemption interface functions | MEDIUM |

### Contracts NOT Modified Since v3.2 (Lower Risk)

These contracts were fully audited in v3.2 and have not changed since. They still need a check but are lower priority:

DegenerusQuests, DegenerusJackpots, DegenerusAffiliate, DegenerusDeityPass, WrappedWrappedXRP, Icons32Data, DegenerusTraitUtils, DeityBoonViewer, JackpotModule, MintModule, DegeneretteModule, DecimatorModule, WhaleModule, EndgameModule, GameOverModule, BoonModule, PayoutUtils, MintStreakUtils, IDegenerusGame, IDegenerusQuests, IDegenerusAffiliate, IDegenerusCoin, IStETH, IVaultCoin, IVRFCoordinator, DegenerusGameModuleInterfaces, ContractAddresses, all 5 libraries.

### Recommended Batching Strategy (6 Plans)

| Plan | Scope | Files | ~Lines | Rationale |
|------|-------|-------|--------|-----------|
| 54-01 | High-Risk Core: Game + Stonk tokens | DegenerusGame.sol, StakedDegenerusStonk.sol, DegenerusStonk.sol | ~4,005 | Most modified contracts; gambling burn + redemption lootbox changes |
| 54-02 | High-Risk Modules: Advance + Lootbox | AdvanceModule.sol, LootboxModule.sol | ~3,267 | Skim redesign + lootbox split; newest code |
| 54-03 | Medium-Risk: Coinflip + Token + Interfaces | BurnieCoinflip.sol, BurnieCoin.sol, IBurnieCoinflip.sol, IStakedDegenerusStonk.sol, IDegenerusGameModules.sol | ~2,540 | v3.3 gambling burn changes, interface NatSpec |
| 54-04 | Core + Storage: Admin, Vault, Storage | DegenerusAdmin.sol, DegenerusVault.sol, GameStorage.sol | ~3,453 | Fix commit changes + storage layout verification |
| 54-05 | Game Modules Batch: Jackpot through Boon | JackpotModule, MintModule, DegeneretteModule, DecimatorModule, WhaleModule, EndgameModule, GameOverModule, BoonModule, PayoutUtils, MintStreakUtils | ~8,327 | Unchanged since v3.2; verification pass |
| 54-06 | Peripheral + Interfaces + Libraries | Quests, Jackpots, Affiliate, DeityPass, WrappedWrappedXRP, TraitUtils, DeityBoonViewer, Icons32Data, ContractAddresses, remaining interfaces, all 5 libraries | ~5,028 | Unchanged since v3.2; quick verification pass |

### NatSpec Patterns to Verify

For each function, check ALL of:
1. **@notice** -- Does the one-line summary accurately describe the function's purpose?
2. **@dev** -- Do implementation notes match actual logic? Are caller lists complete? Are CEI notes accurate?
3. **@param** -- Does each param tag match the actual parameter name AND correctly describe its purpose?
4. **@return** -- Does each return tag match the actual return variable AND correctly describe what is returned?
5. **@custom:reverts** -- Does each custom revert tag match an actual revert path in the implementation?
6. **@inheritdoc** -- Does the base contract's NatSpec accurately describe the overriding implementation?
7. **Block comments** (section headers, overview blocks) -- Do they accurately describe the section's contents?
8. **Inline comments** (`//`) -- Do they accurately describe the adjacent code?

### Finding Format

Use established format from v3.1/v3.2:
```
| ID | Severity | Contract | Line | Summary | Recommendation |
```

Finding ID namespace: `CMT-V35-NNN` for new findings in this phase.
Severity: LOW (wardens will file), INFO (cosmetic, low warden impact).

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Cross-referencing function behavior | Re-auditing function logic | Prior audit verdicts from v3.0-v3.4 | Behavior already proven; comment audit verifies documentation, not logic |
| Finding deduplication | Manual comparison against 114 prior findings | Check CMT/DRIFT/LOW/INFO IDs from v3.1 + v3.2 consolidated reports | Established numbering prevents re-reporting fixed issues |
| Storage layout verification | Manual byte offset counting | Storage.sol header diagram + `forge inspect` if needed | Diagram is the source; only verify comments match it |

## Common Pitfalls

### Pitfall 1: Re-Reporting Fixed Findings
**What goes wrong:** Flagging issues that were already found in v3.1/v3.2 and subsequently fixed.
**Why it happens:** The prior findings reports list 114 total findings (84 v3.1 + 30 v3.2). Many were fixed in code but the findings reports still list them.
**How to avoid:** Before reporting any finding, check it against the v3.1 and v3.2 consolidated findings. If it matches an existing ID, verify the current state -- if fixed, skip it. Only report if the fix is wrong or the issue persists.
**Warning signs:** Finding description matches verbatim text from a prior report.

### Pitfall 2: False Positives from Interface vs Implementation NatSpec
**What goes wrong:** Flagging interface NatSpec as incorrect when it intentionally describes the contract-level behavior (not the low-level implementation).
**Why it happens:** Interfaces describe the public API contract. Implementation details (e.g., delegatecall routing) are intentionally omitted.
**How to avoid:** Check both the interface AND implementation. Interface @dev can legitimately omit implementation details. Flag only when the interface NatSpec contradicts the actual behavior observable to callers.
**Warning signs:** Flagging "missing @param" on an interface function that uses @inheritdoc in the implementation.

### Pitfall 3: Flagging Intentional Design as Stale Comments
**What goes wrong:** Flagging comments about design decisions as "stale" when they describe intentional behavior.
**Why it happens:** KNOWN-ISSUES.md documents several intentional design decisions (e.g., stETH rounding, non-VRF affiliate entropy, _sendToVault hard reverts).
**How to avoid:** Cross-reference KNOWN-ISSUES.md before flagging any comment about design decisions.
**Warning signs:** Comment describes behavior that matches a KNOWN-ISSUES.md entry.

### Pitfall 4: Missing New NatSpec on New Code
**What goes wrong:** Assuming new code from v3.3/v3.4 has complete NatSpec when it was added hastily.
**Why it happens:** Code changes often focus on correctness, with NatSpec added as an afterthought.
**How to avoid:** Pay special attention to functions and parameters added in v3.3/v3.4. Check that new functions have complete @notice/@dev/@param/@return coverage.
**Warning signs:** Functions with no NatSpec or only partial tags in recently-modified files.

### Pitfall 5: Comment Fixes That Introduce New Errors
**What goes wrong:** The `fba43f2c` fix commit corrected several NatSpec issues, but the fix text itself may be inaccurate.
**Why it happens:** v3.2 Pattern 3 found exactly this issue -- v3.1 fixes that replaced wrong text with different wrong text (e.g., CMT-029 fix replaced "loot box awards" with "auto-rebuy tickets" instead of the correct "whale pass claims").
**How to avoid:** For every file modified in the fix commit, verify the NEW NatSpec text is accurate against the actual code, not just that the old issue is gone.
**Warning signs:** NatSpec that was recently modified (visible in git blame) but uses imprecise terminology.

## Known Prior Findings Status

### v3.2 Findings: Current Resolution State

The `fba43f2c` commit resolved the last 4 outstanding v3.2 findings. All 30 v3.2 findings are now addressed:
- 26 were fixed in v3.1/v3.3 code changes (before v3.4)
- 4 were fixed in the `fba43f2c` bulk fix commit (CMT-003, CMT-201, INFO-01, OQ-1)

**Findings that had lingering issues in v3.2 and need verification of their fix:**
| ID | Contract | What Was Fixed | Verify In |
|----|----------|---------------|-----------|
| CMT-003 | GameStorage.sol | Slot 0 tail vs Slot 1 boundary comment | Plan 54-04 |
| CMT-201 | DegenerusVault.sol | Plural "checks" -> singular | Plan 54-04 |
| INFO-01 | BurnieCoin.sol | Conservative underreport documented | Plan 54-03 |
| OQ-1 | DegenerusAdmin.sol | Non-reset documented as intentional | Plan 54-04 |
| F-50-01 | AdvanceModule.sol | Full 256-bit modulo documented | Plan 54-02 |
| F-50-02 | AdvanceModule.sol | Bit overlap documented | Plan 54-02 |
| F-51-01 | StakedDegenerusStonk.sol | Rounding dust documented | Plan 54-01 |
| F-51-02 | StakedDegenerusStonk.sol | uint96 safety margin documented | Plan 54-01 |

### v3.2 Findings That Were "Accept as Known" (May Still Be Open)

These were categorized as LOW priority in v3.2 and may or may not have been addressed:
| ID | Contract | Issue | Status to Verify |
|----|----------|-------|-----------------|
| CMT-V32-003 | LootboxModule | PlayerCredited event missing @param recipient | Check in Plan 54-02 |
| CMT-V32-004 | AdvanceModule | wireVrf missing @param keyHash_ | Check in Plan 54-02 |
| CMT-059 | BurnieCoin | _burn @dev lists only 2 of 4 callers | Check in Plan 54-03 |
| CMT-060 | BurnieCoin | VaultAllowanceSpent "without minting" false for vaultMintTo | Check in Plan 54-03 |
| CMT-102 | BurnieCoinflip | "takeprofit" parenthetical | Check in Plan 54-03 |
| CMT-104 | DegenerusJackpots | OnlyCoin says "coinflip contract" but accepts COIN+COINFLIP | Check in Plan 54-05 |
| CMT-208 | IDegenerusGame | 3 terminal dec functions lack NatSpec | Check in Plan 54-06 |
| CMT-209 | IDegenerusGame | 4 Degenerette view functions lack NatSpec | Check in Plan 54-06 |
| CMT-057 | WrappedWrappedXRP | Section header line 279 | Check in Plan 54-06 |
| CMT-058 | WrappedWrappedXRP | VaultAllowanceSpent @param | Check in Plan 54-06 |
| CMT-079 | ContractAddresses | "zeroed in source" comment | Check in Plan 54-06 |
| NEW-002 | DegenerusGame | Incomplete module list (5 of 9) | Check in Plan 54-01 |
| CMT-V32-002 | JackpotModule | "BURNIE only, no ETH bonuses" inline | Check in Plan 54-05 |
| CMT-V32-005 | MintModule | @return writesUsed "queue entries" | Check in Plan 54-05 |
| CMT-V32-006 | DecimatorModule | @return "or expired" | Check in Plan 54-05 |
| CMT-205 | IDegenerusGame | decClaimable "or expired" | Check in Plan 54-06 |
| CMT-206 | IDegenerusGame | Duplicate stale @notice | Check in Plan 54-06 |
| CMT-061 | WrappedWrappedXRP | EVENTS header references "wrap" | Check in Plan 54-06 |
| CMT-101 | BurnieCoinflip | Unused TakeProfitZero error | Check in Plan 54-03 |
| CMT-V32-001 | JackpotModule | @return ticketSpent wrong | Check in Plan 54-05 |
| DRIFT-V32-001 | GameOverModule | _sendToVault hard-revert undocumented | Check in Plan 54-05 |
| CMT-207 | IDegenerusGame | Phantom useBoon parameter | Check in Plan 54-06 |
| NEW-001 | DegenerusAdmin | "liveness" in interface @dev | Check in Plan 54-04 |

### v3.2 Cross-Cutting Patterns to Watch For

1. **Stale NatSpec after code removal** (7 findings in v3.2) -- Grep for references to removed features
2. **Incomplete NatSpec on partially-documented functions** (5 findings) -- Partial docs worse than none
3. **Fix text substitution errors** (2 findings) -- Verify fix text accuracy
4. **Interface @dev/header stale after refactoring** (3 findings) -- Check headers match current function set
5. **Stale v3.1 findings not fixed** (4 findings) -- All should now be resolved by `fba43f2c`
6. **Event NatSpec inaccuracies** (2 findings) -- Check event @notice/@param against emit sites

## Code Examples

### NatSpec Verification Pattern

For each function, the auditor should verify:
```solidity
// Example: check that @param names match function signature
/// @param player The player making the deposit    <-- verify "player" matches param name
/// @param amount Amount of BURNIE to deposit       <-- verify "amount" matches param name
function depositCoinflip(address player, uint256 amount) external;
//                              ^^^^^^          ^^^^^^
//                              Must match @param names exactly
```

### Stale Reference Detection Pattern
```solidity
// WRONG: references removed feature
/// @dev Claims are blocked during RNG lock period
// But rngLocked guard was removed from claim functions in v3.3

// RIGHT: updated for current behavior
/// @dev Claims proceed regardless of RNG lock state
```

### Interface vs Implementation Consistency
```solidity
// Interface:
/// @notice Claim coinflip winnings
/// @return claimed Amount actually claimed
function claimCoinflips(address player, uint256 amount) external returns (uint256 claimed);

// Implementation must match:
// - Same param names
// - Return value semantics match description
// - No @custom:reverts tags for reverts that don't exist
```

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Foundry + Hardhat |
| Config file | foundry.toml, hardhat.config.js |
| Quick run command | N/A -- this is a manual audit phase |
| Full suite command | N/A |

### Phase Requirements -> Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| CMT-01 | NatSpec matches code | manual-only | N/A -- human review of comment accuracy | N/A |
| CMT-02 | No stale references | manual-only | N/A -- requires semantic understanding | N/A |
| CMT-03 | Inline comments accurate | manual-only | N/A -- requires semantic understanding | N/A |
| CMT-04 | Findings documented | manual-only | N/A -- deliverable format check | N/A |

**Justification for manual-only:** Comment correctness is a semantic verification task. Automated tools cannot determine whether a comment accurately describes code behavior. The closest automated check would be NatSpec completeness (missing @param tags), but even that requires judgment about whether partial documentation is intentional.

### Sampling Rate
- **Per task commit:** Visual review of findings file format
- **Per wave merge:** Cross-reference findings against prior reports for deduplication
- **Phase gate:** All 46 files audited, all findings documented

### Wave 0 Gaps
None -- no test infrastructure needed for a manual audit phase.

## Sources

### Primary (HIGH confidence)
- `audit/v3.1-findings-consolidated.md` -- 84 v3.1 findings with established patterns
- `audit/v3.2-findings-consolidated.md` -- 30 v3.2 findings with 6 cross-cutting patterns
- `audit/v3.4-findings-consolidated.md` -- 5 v3.4 findings (3 comment-related)
- `git log --name-only` -- Verified which contracts were modified in v3.3/v3.4
- `git show fba43f2c` -- Verified fix commit scope (7 contracts, 21 insertions / 5 deletions)
- Direct file reads of all contract directories for line counts and inventory

### Secondary (MEDIUM confidence)
- Prior phase research files (Phase 29 and Phase 39 RESEARCH.md) -- Established methodology

## Metadata

**Confidence breakdown:**
- Contract inventory: HIGH -- verified by direct file listing
- Prior findings status: HIGH -- verified fix commit contents and grep for remaining issues
- Batching strategy: HIGH -- based on file size data and modification history
- Pitfall identification: HIGH -- derived from actual v3.1/v3.2 cross-cutting patterns

**Research date:** 2026-03-21
**Valid until:** 2026-04-21 (stable -- contract code is frozen for C4A)
