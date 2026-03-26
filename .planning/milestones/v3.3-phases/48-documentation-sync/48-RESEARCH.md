# Phase 48: Documentation Sync - Research

**Researched:** 2026-03-21
**Domain:** NatSpec correctness, error naming, and audit documentation synchronization for Solidity smart contracts
**Confidence:** HIGH

## Summary

This phase is a documentation-only sweep across the 6 gambling burn files and the full audit documentation suite. No new libraries, tools, or architectural patterns are needed -- the work is reading code, verifying comments match implementation, fixing one misleading error name, adding a bit allocation comment, and updating 20 audit docs to reflect v3.3 findings and fixes.

The 6 changed files total 3,875 lines: StakedDegenerusStonk.sol (802), DegenerusStonk.sol (247), BurnieCoinflip.sol (1,127), DegenerusGameAdvanceModule.sol (1,423), interfaces/IStakedDegenerusStonk.sol (93), interfaces/IBurnieCoinflip.sol (183). Four code fixes were applied during Phase 45 (CP-08, CP-06, Seam-1, CP-07), and NatSpec must accurately describe the post-fix behavior. The error name `OnlyBurnieCoin` is reused in two locations where the actual access restriction is "only sDGNRS" or "only approved operator," which would confuse wardens. The audit docs (20 files in `audit/`) predate the gambling burn mechanism entirely and must be updated.

**Primary recommendation:** Split into 3-4 plans: (1) NatSpec verification + error name fix across the 6 files (DOC-01 + DOC-03), (2) bit allocation map comment in rngGate (DOC-02), (3-4) audit doc sync (DOC-04) across the 20 doc files. Plans should be sequential -- NatSpec and error name fixes must land before audit docs reference the final code.

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| DOC-01 | NatSpec correctness for all 6 changed files | Full file inventory below with known issues: malformed `///` on BurnieCoinflip line 342, StakedDegenerusStonk `claimRedemption` NatSpec needs `flipWon` parameter accuracy check, interface NatSpec for `claimCoinflipsForRedemption` still says "OnlyBurnieCoin" revert |
| DOC-02 | Bit allocation map comment in `rngGate()` | Complete bit usage analysis below: bit 0 = coinflip win/loss, bits 8+ = redemption roll, full word = jackpot/lootbox/variance (via keccak/modulo) |
| DOC-03 | Error name fix -- `claimCoinflipsForRedemption` uses `OnlyBurnieCoin` (misleading) | Three locations identified: line 99 (error declaration), line 348 (sDGNRS access check), line 1115 (operator approval check). New error name(s) needed. Interface NatSpec also references `OnlyBurnieCoin` for this function. |
| DOC-04 | Full audit doc sync -- update all 13+ audit reference docs for gambling burn mechanism | 20 files in `audit/` directory need review. Key updates: FINAL-FINDINGS-REPORT.md (add v3.3 HIGH/MEDIUM findings and fixes), KNOWN-ISSUES.md (add gambling burn design mechanics), EXTERNAL-AUDIT-PROMPT.md (add redemption system to scope/mechanics), plus 17 individual findings docs need version stamps. |
</phase_requirements>

## Standard Stack

No new tools are needed. This is a pure code-editing and documentation phase.

### Core
| Tool | Version | Purpose | Why Standard |
|------|---------|---------|--------------|
| Solidity 0.8.34 | 0.8.34 | Source language for NatSpec edits | Project compiler version |
| Foundry | v1.0 | Compilation verification after error rename | Already installed, `foundry.toml` configured |

### Supporting
| Tool | Purpose | When to Use |
|------|---------|-------------|
| `forge build` | Verify compilation after DOC-03 error rename | After renaming error in BurnieCoinflip.sol |
| `forge test` | Verify no test regressions after error rename | After DOC-03 changes |

### Alternatives Considered
None. This is a documentation sweep -- no tooling choices involved.

## Architecture Patterns

### File-by-File NatSpec Verification Strategy

For each of the 6 files, systematically verify every `@notice`, `@dev`, `@param`, `@return`, `@custom:reverts` tag against the actual implementation. The verification must cover:

1. **Function signature match:** Every `@param` and `@return` corresponds to an actual parameter/return value
2. **Behavior accuracy:** `@dev` descriptions match the code's actual behavior post-fixes
3. **Access control accuracy:** `@custom:reverts` conditions match actual revert paths
4. **Cross-reference consistency:** Interface NatSpec matches implementation NatSpec

### The 6 Changed Files

```
contracts/
  StakedDegenerusStonk.sol     (802 lines)  -- primary orchestrator, most NatSpec
  DegenerusStonk.sol           (247 lines)  -- wrapper, Seam-1 fix added GameNotOver
  BurnieCoinflip.sol           (1127 lines) -- DOC-03 error name fix here
  modules/
    DegenerusGameAdvanceModule.sol (1423 lines) -- DOC-02 bit map here, CP-06 fix
  interfaces/
    IStakedDegenerusStonk.sol  (93 lines)   -- gambling burn interface additions
    IBurnieCoinflip.sol        (183 lines)  -- claimCoinflipsForRedemption NatSpec
```

### Anti-Patterns to Avoid
- **Editing NatSpec without re-reading the code:** After 4 code fixes (CP-08, CP-06, Seam-1, CP-07), the implementation has changed. NatSpec must be verified against the CURRENT code, not the pre-fix version.
- **Updating error names without updating all references:** The `OnlyBurnieCoin` error is used in 3 code locations AND referenced in NatSpec in the interface. All must be updated atomically.
- **Updating audit docs piecemeal:** All 20 audit docs should be updated in a coordinated pass so cross-references are consistent.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| NatSpec verification | Manual read-through from memory | Systematic file-by-file comparison: read function signature, read NatSpec, verify match | Easy to miss subtle mismatches (e.g., outdated `@custom:reverts` after code fix) |
| Error rename propagation | Manual find-and-replace | `grep -rn OnlyBurnieCoin contracts/` to find ALL references before renaming | Missing one reference breaks compilation |

## Common Pitfalls

### Pitfall 1: Stale NatSpec After Code Fix (Cross-Cutting Pattern from v3.1/v3.2)
**What goes wrong:** A code fix changes behavior but NatSpec is not updated. Wardens reading NatSpec are misled about what the code does.
**Why it happens:** Code fixes focus on logic correctness, not documentation. The v3.1 audit found 84 comment inaccuracies and the v3.2 audit found 30 more -- this is a recurring pattern.
**How to avoid:** For each of the 4 code fixes (CP-08, CP-06, Seam-1, CP-07), explicitly verify that NatSpec on the modified functions reflects the fix.
**Warning signs:** NatSpec that describes the pre-fix behavior (e.g., "BURNIE requires coinflip resolution" without mentioning the split-claim path).

### Pitfall 2: Error Name Rename Breaking Compilation
**What goes wrong:** Renaming `OnlyBurnieCoin` to a new name but missing one usage site, causing `forge build` to fail.
**Why it happens:** The error is used in 3 code locations (lines 99, 203, 348, 1115) and referenced in interface NatSpec.
**How to avoid:** Grep for `OnlyBurnieCoin` across ALL files in `contracts/` before and after renaming. Verify with `forge build`.
**Warning signs:** Compilation errors mentioning undefined identifier.

### Pitfall 3: Audit Doc Inconsistencies
**What goes wrong:** FINAL-FINDINGS-REPORT.md says "No open findings" while the actual findings from Phase 44 (3 HIGH, 1 MEDIUM) are now fixed but should be documented.
**Why it happens:** The audit docs were last updated before v3.3 work began. The findings were confirmed and fixed, but this needs to be recorded.
**How to avoid:** Update FINAL-FINDINGS-REPORT.md, KNOWN-ISSUES.md, and EXTERNAL-AUDIT-PROMPT.md as a coordinated set.
**Warning signs:** Audit docs that don't mention the gambling burn mechanism at all.

### Pitfall 4: Interface vs Implementation NatSpec Drift
**What goes wrong:** Interface NatSpec says one thing, implementation NatSpec says another. Wardens see whichever version their tooling surfaces.
**Why it happens:** Interfaces and implementations are edited independently.
**How to avoid:** After updating implementation NatSpec, explicitly cross-check against the corresponding interface.
**Warning signs:** IBurnieCoinflip.sol line 172 says `@dev Only callable by sDGNRS contract` but does NOT mention the misleading error name.

## Code Examples

### DOC-02: Bit Allocation Map for rngGate()

The following bit consumers have been identified by tracing every usage of the VRF word (`currentWord`) after `_applyDailyRng()`:

```solidity
// BIT ALLOCATION MAP for VRF random word (currentWord after _applyDailyRng):
//
// Bit(s)   Consumer                    Operation                         Location
// ------   --------                    ---------                         --------
// 0        Coinflip win/loss           rngWord & 1                       BurnieCoinflip.sol:808
// 8+       Redemption roll             (currentWord >> 8) % 151 + 25     AdvanceModule.sol:773
// full     Coinflip reward percent     keccak256(rngWord, epoch) % 20    BurnieCoinflip.sol:782-787
// full     Jackpot winner selection    via delegatecall (full word)      JackpotModule (payDailyJackpot)
// full     Coin jackpot                via delegatecall (full word)      JackpotModule (_payDailyCoinJackpot)
// full     Lootbox RNG                 stored as lootboxRngWordByIndex   AdvanceModule.sol:804
// full     Future take variance        rngWord % (variance * 2 + 1)     AdvanceModule.sol:1010
// full     Prize pool consolidation    via delegatecall (full word)      JackpotModule (consolidatePrizePools)
// full     Final day DGNRS reward      via delegatecall (full word)      JackpotModule (awardFinalDayDgnrsReward)
// full     Reward jackpots             via delegatecall (full word)      JackpotModule (_runRewardJackpots)
//
// NOTE: Bits 0 and 8+ are the only direct bit-level consumers.
//       All "full" consumers use modular arithmetic or keccak mixing,
//       so bit overlap with bits 0 and 8+ is not a collision concern.
```

### DOC-03: Error Name Fix

Current code in BurnieCoinflip.sol:
```solidity
// Line 99: Error declaration
error OnlyBurnieCoin();

// Line 203: Modifier (legitimate use -- caller IS BurnieCoin)
modifier onlyBurnieCoin() {
    if (msg.sender != address(burnie)) revert OnlyBurnieCoin();
    _;
}

// Line 348: sDGNRS access check (MISLEADING -- caller is sDGNRS, not BurnieCoin)
function claimCoinflipsForRedemption(...) external returns (uint256 claimed) {
    if (msg.sender != ContractAddresses.SDGNRS) revert OnlyBurnieCoin(); // WRONG NAME
    return _claimCoinflipsAmount(player, amount, true);
}

// Line 1115: Operator approval check (MISLEADING -- this is about operator approval)
function _resolvePlayer(address player) private view returns (address resolved) {
    if (player != msg.sender) {
        if (!degenerusGame.isOperatorApproved(player, msg.sender)) {
            revert OnlyBurnieCoin(); // Reusing error -- WRONG NAME
        }
    }
    ...
}
```

**Fix approach:** The cleanest solution is to:
1. Add a new `OnlyStakedDegenerusStonk()` error for line 348 (sDGNRS access check)
2. Add `NotApproved()` error for line 1115 (or reuse the existing `NotApproved` from `_requireApproved` on line 1124)
3. Keep `OnlyBurnieCoin()` for the `onlyBurnieCoin` modifier (line 203) since that IS checking for BurnieCoin
4. Update IBurnieCoinflip.sol NatSpec to reference the correct error names

Note: Line 1115 already has `NotApproved()` declared and used in `_requireApproved` (line 1124). The `_resolvePlayer` function should use `NotApproved()` instead of `OnlyBurnieCoin()` for consistency. The comment "// Reusing error" on line 1115 explicitly acknowledges this is a hack.

### DOC-04: Audit Doc Update Inventory

20 files in `audit/` directory:

| File | Update Needed | Severity |
|------|---------------|----------|
| `FINAL-FINDINGS-REPORT.md` | Add v3.3 gambling burn findings (3 HIGH fixed, 1 MEDIUM fixed). Update executive summary, scope, risk assessment. | HIGH -- wardens read this first |
| `KNOWN-ISSUES.md` | Add gambling burn design mechanics (split-claim, RNG-dependent burn, 50% cap). | HIGH |
| `EXTERNAL-AUDIT-PROMPT.md` | Add redemption system to scope, core mechanics, code scope, and required coverage. | HIGH |
| `v3.1-findings-consolidated.md` | Add v3.3 version stamp noting gambling burn changes post-v3.1. | LOW |
| `v3.1-findings-31-core-game-contracts.md` | Mention gambling burn changes to AdvanceModule. | LOW |
| `v3.1-findings-34-token-contracts.md` | Mention gambling burn changes to sDGNRS/DGNRS. | LOW |
| `v3.1-findings-35-peripheral-contracts.md` | Mention gambling burn changes to BurnieCoinflip. | LOW |
| `v3.2-findings-consolidated.md` | Add v3.3 version stamp. | LOW |
| `v3.2-findings-40-token-contracts.md` | Note gambling burn changes. | LOW |
| `v3.2-findings-40-core-game-contracts.md` | Note AdvanceModule changes. | LOW |
| `v3.2-rng-delta-findings.md` | Note new RNG consumer (redemption roll). | MEDIUM |
| `v3.2-governance-fresh-eyes.md` | No changes needed (governance unchanged). | NONE |
| `v3.2-findings-39-*.md` (5 files) | No changes needed (modules unchanged). | NONE |
| `v3.1-findings-32-*.md` | No changes needed (modules unchanged). | NONE |
| `v3.1-findings-33-*.md` | No changes needed (modules unchanged). | NONE |
| `PAYOUT-SPECIFICATION.html` | May need gambling burn payout rules added. | MEDIUM |

**Priority tiers:**
- **Tier 1 (must update):** FINAL-FINDINGS-REPORT.md, KNOWN-ISSUES.md, EXTERNAL-AUDIT-PROMPT.md
- **Tier 2 (should update):** v3.2-rng-delta-findings.md, PAYOUT-SPECIFICATION.html
- **Tier 3 (version stamp only):** consolidated findings docs, individual findings docs referencing changed files

## State of the Art

| Old State (pre-v3.3) | Current State (post-v3.3) | Impact |
|----------------------|--------------------------|--------|
| `_deterministicBurnFrom` did not subtract pending reserves | Fixed: subtracts `pendingRedemptionEthValue` and `pendingRedemptionBurnie` | CP-08 NatSpec must reflect deduction |
| `_gameOverEntropy` did not resolve redemptions | Fixed: resolves redemptions in both VRF and fallback paths | CP-06 NatSpec must document resolution |
| `DGNRS.burn()` allowed during active game | Fixed: reverts with `GameNotOver()` during active game | Seam-1 NatSpec must document revert |
| `claimRedemption()` required full coinflip resolution | Fixed: split-claim pays ETH always, BURNIE conditional on flip | CP-07 NatSpec must describe split-claim |
| No gambling burn system | 7 new state variables, 3 new structs, ~383 new lines | All NatSpec is new and needs verification |
| `OnlyBurnieCoin` error used for sDGNRS access | Misleading -- needs rename | DOC-03 |

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Foundry (forge) + Hardhat |
| Config file | `foundry.toml` |
| Quick run command | `forge build` |
| Full suite command | `forge test` |

### Phase Requirements to Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| DOC-01 | NatSpec matches implementation | manual-only | N/A -- human review | N/A |
| DOC-02 | Bit allocation comment exists | manual-only | N/A -- verify comment in source | N/A |
| DOC-03 | Error name fixed, code compiles | unit | `forge build` | Existing tests cover error paths |
| DOC-04 | Audit docs updated | manual-only | N/A -- human review | N/A |

### Sampling Rate
- **Per task commit:** `forge build` (DOC-03 only)
- **Per wave merge:** `forge test` (verify no regressions from error rename)
- **Phase gate:** `forge build` green + manual NatSpec review complete

### Wave 0 Gaps
None -- existing test infrastructure covers the error rename compilation check. NatSpec and doc updates are inherently manual-review tasks with no automated verification possible.

## Open Questions

1. **PAYOUT-SPECIFICATION.html update scope**
   - What we know: This is an HTML file describing payout rules. The gambling burn adds a new payout mechanism (RNG-rolled ETH + coinflip-conditional BURNIE).
   - What's unclear: Whether the HTML file is auto-generated or manually maintained, and whether it needs gambling burn rules or is considered out of scope.
   - Recommendation: Read the file during planning to determine if it needs updates.

2. **Error rename scope for tests**
   - What we know: Renaming `OnlyBurnieCoin` to `OnlyStakedDegenerusStonk` on line 348 will need grep across test files too.
   - What's unclear: Whether any test files reference `OnlyBurnieCoin` in assertion checks.
   - Recommendation: Grep test directory for `OnlyBurnieCoin` during DOC-03 implementation.

## Sources

### Primary (HIGH confidence)
- Direct source code analysis of all 6 changed files in `contracts/`
- Phase 44 research (`.planning/phases/44-delta-audit-redemption-correctness/44-RESEARCH.md`) -- file inventory, architecture, finding details
- Phase 45 summary (`.planning/phases/45-invariant-test-suite/45-01-SUMMARY.md`) -- code fix details for CP-08, CP-06, Seam-1, CP-07
- All 20 audit docs in `audit/` directory -- current state of documentation

### Secondary (MEDIUM confidence)
- v3.1 and v3.2 consolidated findings -- cross-cutting patterns for stale NatSpec (Pattern 1: 7 findings, Pattern 2: 5 findings)

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH -- no new tools, pure documentation
- Architecture: HIGH -- all files and issues identified from direct source reading
- Pitfalls: HIGH -- informed by v3.1/v3.2 patterns (114 prior comment findings)

**Research date:** 2026-03-21
**Valid until:** 2026-04-21 (stable -- documentation changes are not time-sensitive)
