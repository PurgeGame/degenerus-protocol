# Phase 55: Gas Optimization - Research

**Researched:** 2026-03-21
**Domain:** Solidity storage layout analysis, dead code detection, gas optimization across 34 contracts
**Confidence:** HIGH

## Summary

Phase 55 is an audit-only gas optimization pass across all 34 Degenerus Protocol contracts (~26,300 lines Solidity 0.8.34). The deliverable is a findings document, NOT code changes. This phase is independent of Phase 54 (Comment Correctness) and can run in parallel.

The prior v3.3 Phase 47 gas analysis was narrowly scoped to the 7 new gambling burn / redemption variables in StakedDegenerusStonk.sol. It found all 7 ALIVE and identified 3 packing opportunities (all deferred). Phase 55 must do a FRESH pass across ALL contracts since significant code changes have occurred since v3.3 (v3.4 skim redesign, redemption lootbox, and multiple bug fixes).

The codebase already employs aggressive storage packing in DegenerusGameStorage (Slot 0: 15 variables in 32 bytes, Slot 1: 7 variables in 27 bytes). Most remaining storage variables are mappings (which cannot be packed by design). The primary optimization surface is: (a) confirming no variables became dead after recent refactors, (b) identifying redundant guard checks, (c) documenting any remaining scalar-variable packing opportunities for future redeployment.

**Primary recommendation:** Systematically walk every storage variable declaration across all 34 contracts, trace read+write sites, identify dead code via unreachable branches or unused errors/events, and catalog packing opportunities with estimated savings. Document everything in a single findings file.

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| GAS-01 | All storage variables confirmed alive (read + write in reachable code paths) | Storage layout analysis via `forge inspect` gives complete variable inventory per contract. Liveness analysis pattern established in v3.3 Phase 47: trace declaration, write sites, read sites, delete sites, verdict. |
| GAS-02 | No redundant checks, dead branches, or unreachable code | Grep-based analysis for repeated guard patterns (`gameOver`, `msg.sender !=`), orphaned errors/events, and unreachable branches. Slither 0.11.5 available for automated dead-code detection. |
| GAS-03 | Storage packing opportunities identified with estimated gas savings | `forge inspect <Contract> storageLayout` provides exact slot/offset/bytes for every variable. DegenerusGameStorage has 110 slots (0-109), most are mappings. Packing is only possible between consecutive scalar types. |
| GAS-04 | All findings documented with contract, line ref, and estimated impact | Standard audit findings format established across v3.1-v3.4 milestones. |
</phase_requirements>

## Standard Stack

### Core Tools
| Tool | Version | Purpose | Why Standard |
|------|---------|---------|--------------|
| Forge (`forge inspect`) | 1.5.1-stable | Extract verified storage layouts per contract | Compiler-level accuracy, shows exact slot/offset/bytes |
| Slither | 0.11.5 | Static analysis for dead code, unused variables, redundant checks | Industry-standard Solidity analyzer |
| Solidity Compiler | 0.8.34 | viaIR enabled, optimizer_runs=2 | Project configuration in foundry.toml |

### Supporting
| Tool | Purpose | When to Use |
|------|---------|-------------|
| `grep`/`rg` | Manual variable reference counting | When forge inspect shows a variable, trace all read/write sites |
| `forge inspect storageLayout` | Slot/offset mapping | For every contract with state variables |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Manual liveness trace | Slither `--detect unused-state` | Slither catches obvious dead vars but misses cross-contract delegatecall usage; manual trace is more thorough for this codebase |

## Architecture Patterns

### Contract Organization (relevant to analysis)

The codebase has a specific architecture that affects gas analysis:

```
contracts/
  storage/DegenerusGameStorage.sol   # 1,599 lines - ALL game storage variables
  DegenerusGame.sol                  # 2,919 lines - main contract, inherits storage
  modules/                           # 12 delegatecall modules - share storage layout
  libraries/                         # 5 pure/view libraries - no storage
  BurnieCoinflip.sol                 # 1,129 lines - separate contract, own storage
  BurnieCoin.sol                     # 1,075 lines - separate contract, own storage
  StakedDegenerusStonk.sol           # 837 lines - separate contract, own storage
  [10 other standalone contracts]    # varying sizes, own storage each
```

**Key architectural fact:** DegenerusGame + all 12 modules share the SAME storage layout via `DegenerusGameStorage`. A variable declared in storage may be written by one module and read by another via delegatecall. Liveness analysis MUST check all 13 contracts (DegenerusGame + 12 modules) for each storage variable.

### Analysis Pattern: Variable Liveness

Established in v3.3 Phase 47:

```
For each storage variable:
1. Declaration: file, line, type, slot, offset, bytes
2. Write sites: every assignment (=, +=, -=, delete)
3. Read sites: every read in conditions, computations, returns
4. Delete sites: every `delete` or zero-assignment
5. Verdict: ALIVE (has read + write in reachable paths) or DEAD
```

### Analysis Pattern: Packing Opportunity

```
For each identified opportunity:
1. Current layout: slot(s) used, bytes wasted
2. Proposed layout: how to pack, new slot assignment
3. Bit-width safety: prove no truncation under real values
4. Co-access pattern: are the packed variables read/written together?
5. Gas savings estimate: SLOAD/SSTORE costs saved per transaction
6. Risk: what could go wrong
7. Deployability: whether this requires redeployment (answer: yes, always)
```

### Anti-Patterns to Avoid

- **Cross-module blind spots:** Never conclude a DegenerusGameStorage variable is dead by only checking one module. All 13 inheriting contracts must be searched.
- **Constants vs storage confusion:** Constants (declared with `constant` or `immutable`) do not occupy storage slots. Do NOT include them in liveness analysis.
- **Mapping packing fallacy:** Mappings always occupy their own slot root. Two adjacent mappings CANNOT be packed together. Only consecutive scalar types can pack.
- **Deployed contract reordering:** DegenerusGameStorage explicitly states "SLOT STABILITY: Never reorder, remove, or change types of existing variables." Packing opportunities are for documentation only (future redeployment).

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Storage layout inspection | Manual slot counting | `forge inspect <Contract> storageLayout` | Compiler-verified, catches edge cases in struct packing |
| Dead variable detection | Line-by-line reading | `rg` for all references + Slither `unused-state` | Systematic, catches cross-file references |
| Gas cost estimation | Manual opcode counting | Standard SLOAD=2100/SSTORE=5000-20000 costs | Well-established EVM gas costs |

## Common Pitfalls

### Pitfall 1: Delegatecall Storage Blindness
**What goes wrong:** Analyst checks DegenerusGame.sol for references to a storage variable, finds none, declares it dead. But the variable is used exclusively in a module via delegatecall.
**Why it happens:** DegenerusGameStorage defines variables used across 13 different files.
**How to avoid:** For every DegenerusGameStorage variable, search ALL files in `contracts/` and `contracts/modules/`.
**Warning signs:** A variable with 0 references in DegenerusGame.sol but defined in DegenerusGameStorage.

### Pitfall 2: Packing Opportunities Across Mapping Boundaries
**What goes wrong:** Analyst sees `uint48` at slot 19 and `mapping` at slot 20, suggests packing them. Mappings cannot pack.
**Why it happens:** Mappings always start at their own slot regardless of what precedes them.
**How to avoid:** Only identify packing between CONSECUTIVE SCALAR types. Verify with `forge inspect`.
**Warning signs:** Proposed packing involving any mapping type.

### Pitfall 3: False Dead Variables Due to Conditional Paths
**What goes wrong:** Variable appears unused in normal flow but is critical in gameover, distress mode, or compressed jackpot paths.
**Why it happens:** The game has many conditional code paths (gameOver, phaseTransitionActive, compressedJackpotFlag, distress mode).
**How to avoid:** Trace ALL conditional branches, not just the primary happy path.
**Warning signs:** Variables with "flag" or "cursor" in name that seem to have few references.

### Pitfall 4: Confusing Dead Storage With Dead Code
**What goes wrong:** GAS-01 (storage variables alive) and GAS-02 (no dead branches/code) are distinct requirements. Analyst conflates them.
**Why it happens:** Both relate to "dead" things.
**How to avoid:** Analyze separately. GAS-01 = every declared storage variable has read+write. GAS-02 = no unreachable `if` branches, unused errors, redundant guards.
**Warning signs:** Mixed findings that don't cleanly map to one requirement.

## Code Examples

### Using forge inspect for storage layout

```bash
# Get full storage layout for a contract
forge inspect DegenerusGameStorage storageLayout

# Get storage layout for a standalone contract
forge inspect BurnieCoinflip storageLayout
forge inspect StakedDegenerusStonk storageLayout
forge inspect DegenerusAdmin storageLayout
```

### Storage Layout Key Facts (verified via forge inspect)

**DegenerusGameStorage:** 110 slots (0-109)
- Slot 0: 15 variables, 32/32 bytes used (FULLY PACKED)
- Slot 1: 7 variables, 27/32 bytes used (5 bytes padding)
- Slot 2: currentPrizePool (uint256, full slot)
- Slots 3-16: full-width uint256 and mappings
- Slot 17: 3 variables, 9/32 bytes used (23 bytes padding)
- Slot 18: dailyCarryoverEthPool (uint256, full slot)
- Slot 19: dailyCarryoverWinnerCap (uint16, 2/32 bytes -- 30 bytes wasted)
- Slot 20+: predominantly mappings (each owns full slot)
- Slot 24: 3 variables, 8/32 bytes used (24 bytes padding)
- Slot 43: 3 variables, 13/32 bytes used (19 bytes padding)
- Slot 58: vrfCoordinator (address, 20/32 bytes -- 12 bytes wasted)
- Slot 61: lootboxRngIndex (uint48, 6/32 bytes -- 26 bytes wasted)
- Slot 74: midDayTicketRngPending (bool, 1/32 bytes -- 31 bytes wasted)
- Slot 103: yieldAccumulator (uint256, full slot)
- Slot 104: centuryBonusLevel (uint24, 3/32 bytes -- 29 bytes wasted)
- Slot 106: lastVrfProcessedTimestamp (uint48, 6/32 bytes -- 26 bytes wasted)
- Slot 109: lastTerminalDecClaimRound (struct, 31/32 bytes)

**IMPORTANT NOTE:** Most "wasted" bytes are between MAPPING slots. Since mappings cannot pack, these bytes are STRUCTURALLY wasted. They cannot be reclaimed without reordering ALL storage, which would require a fresh deployment.

### Variable Reference Counting

```bash
# Count all references to a storage variable across all contracts
rg 'dailyCarryoverWinnerCap' contracts/ --type sol

# Check if an error is used anywhere
rg 'TakeProfitZero' contracts/ --type sol
```

### Gas Cost Reference

```
EVM Storage Gas Costs (relevant):
- SLOAD (cold): 2,100 gas
- SLOAD (warm): 100 gas
- SSTORE (zero to non-zero): 20,000 gas
- SSTORE (non-zero to non-zero): 2,900 gas
- SSTORE (non-zero to zero): 2,900 gas + 4,800 gas refund

Packing savings per co-accessed slot:
- Two variables packed = 1 fewer SLOAD (2,100 gas cold, 100 warm)
- If written together: 1 fewer SSTORE (2,900 - 20,000 gas depending on prior value)
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| optimizer_runs=200 | optimizer_runs=2 (foundry.toml) | Current config | Lower runs = smaller bytecode, slightly higher per-call gas. Appropriate for complex contracts near size limit. |
| Direct storage | Bit-packed fields (prizePoolsPacked, mintPacked_) | Existing codebase | Already implemented -- saves SSTOREs on hot paths |
| Separate boon active+day mappings | Could be packed into single mapping(address => uint256) | Potential optimization | Multiple boon types use 2 mappings each (active+day). Could pack bool+uint48 into one slot. |

## Contract-by-Contract Analysis Scope

### Tier 1: Large/Complex (need thorough analysis)
| Contract | Lines | Storage Vars | Notes |
|----------|-------|-------------|-------|
| DegenerusGameStorage.sol | 1,599 | ~80+ (slots 0-109) | Canonical storage for Game+modules |
| DegenerusGame.sol | 2,919 | Inherits storage | Main contract, many functions |
| DegenerusGameJackpotModule.sol | 2,795 | Inherits storage | Largest module |
| DegenerusGameLootboxModule.sol | 1,814 | Inherits storage | Second largest module |
| DegenerusGameAdvanceModule.sol | 1,453 | Inherits storage | Core game loop |
| DegenerusGameMintModule.sol | 1,199 | Inherits storage | Minting logic |
| DegenerusGameDegeneretteModule.sol | 1,179 | Inherits storage | Roulette bets |
| BurnieCoinflip.sol | 1,129 | ~7 own vars + structs | Separate contract |
| BurnieCoin.sol | 1,075 | ~4 own vars | Token contract |
| DegenerusVault.sol | 1,050 | ~5 own vars | Two contracts in one file |
| DegenerusGameDecimatorModule.sol | 1,024 | Inherits storage | Decimator logic |

### Tier 2: Medium (moderate analysis)
| Contract | Lines | Storage Vars | Notes |
|----------|-------|-------------|-------|
| DegenerusQuests.sol | 1,598 | ~3 own vars + struct | Quest system |
| StakedDegenerusStonk.sol | 837 | ~3 own vars + structs | Staking/redemption |
| DegenerusWhaleModule.sol | 840 | Inherits storage | Pass purchases |
| DegenerusAffiliate.sol | 840 | ~5 own vars | Affiliate system |
| DegenerusAdmin.sol | 804 | ~6 own vars | Governance |
| DegenerusJackpots.sol | 689 | ~4 own vars | BAF tracking |
| DegenerusGameEndgameModule.sol | 540 | Inherits storage | Level transitions |

### Tier 3: Small/Simple (quick scan)
| Contract | Lines | Notes |
|----------|-------|-------|
| DegenerusDeityPass.sol | 392 | NFT, minimal storage |
| WrappedWrappedXRP.sol | 389 | Token wrapper |
| DegenerusGameBoonModule.sol | 359 | Boon logic |
| JackpotBucketLib.sol | 307 | Pure library |
| DegenerusStonk.sol | 249 | Simple token |
| DegenerusGameGameOverModule.sol | 235 | Terminal logic |
| Icons32Data.sol | 228 | Data contract |
| DegenerusTraitUtils.sol | 183 | Pure utils |
| DeityBoonViewer.sol | 171 | View-only |
| DegenerusGamePayoutUtils.sol | 94 | Pure utils |
| BitPackingLib.sol | 88 | Pure library |
| DegenerusGameMintStreakUtils.sol | 62 | Pure utils |
| PriceLookupLib.sol | 47 | Pure library |
| ContractAddresses.sol | 38 | Constants only |
| GameTimeLib.sol | 35 | Pure library |
| EntropyLib.sol | 24 | Pure library |

### Libraries (NO storage analysis needed)
These are `library` or use only `pure`/`view` functions with no state:
- BitPackingLib.sol, EntropyLib.sol, GameTimeLib.sol, JackpotBucketLib.sol, PriceLookupLib.sol
- DegenerusTraitUtils.sol, DegenerusGameMintStreakUtils.sol, DegenerusGamePayoutUtils.sol
- DeityBoonViewer.sol (view-only, reads Game storage)
- ContractAddresses.sol (constants only)

## Known Prior Findings

### v3.3 Phase 47 (subset -- sDGNRS only)
- 7 variables in StakedDegenerusStonk.sol: ALL ALIVE
- 3 packing opportunities identified (all deferred, LOW to LOW-MED priority):
  1. Pack lootbox index + burned count
  2. Pack ethBase + burnieBase
  3. Restructure PendingRedemption struct

### v3.2 Findings (carried forward, relevant to GAS-02)
- CMT-101 (INFO): `TakeProfitZero` orphaned error in BurnieCoinflip -- ALREADY FIXED (removed)

### v2.0 Phase 23 (historical)
- Dead code removal was performed during v2.0 C4A audit prep

## Boon Mapping Packing Pattern (Key Optimization Surface)

DegenerusGameStorage has many boon-type mappings that follow a pattern of paired `active` + `day` mappings:

```
lootboxBoon5Active   (mapping(address => bool))     -- Slot 27
lootboxBoon5Day      (mapping(address => uint48))    -- Slot 28
lootboxBoon15Active  (mapping(address => bool))      -- Slot 29
lootboxBoon15Day     (mapping(address => uint48))    -- Slot 30
lootboxBoon25Active  (mapping(address => bool))      -- Slot 31
lootboxBoon25Day     (mapping(address => uint48))    -- Slot 32
```

Each mapping occupies its own slot root. Since mappings store values at `keccak256(key, slot)`, each player's `active` (bool, 1 byte) and `day` (uint48, 6 bytes) are in DIFFERENT storage slots. If these were packed into a single `mapping(address => uint256)` with `bool` and `uint48` bit-packed, it would save 1 SLOAD per boon check.

However, this requires contract redeployment and storage layout change. For the audit, this should be documented as a GAS-INFO finding with estimated savings.

**Estimated savings per boon check:** 2,100 gas (1 cold SLOAD avoided) or 100 gas (1 warm SLOAD avoided).

**Similar pattern in deity boon tracking:**
- 10 separate `mapping(address => uint48)` for deity boon days (slots 75-85)
- Could theoretically be packed into fewer mappings with bit-packing

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Hardhat + Foundry (dual stack) |
| Config file | `foundry.toml` (Foundry), `hardhat.config.js` (Hardhat) |
| Quick run command | `forge test --match-path 'test/fuzz/*' -vv` |
| Full suite command | `npm test` (1,463 tests) |

### Phase Requirements -> Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| GAS-01 | All storage vars confirmed alive | manual-only | N/A -- audit analysis, not runtime test | N/A |
| GAS-02 | No redundant checks, dead branches | manual-only | `slither . --detect dead-code` (partial) | N/A |
| GAS-03 | Storage packing opportunities identified | manual-only | `forge inspect <Contract> storageLayout` (tooling, not test) | N/A |
| GAS-04 | All findings documented | manual-only | N/A -- deliverable is a document | N/A |

**Justification for manual-only:** This is an audit analysis phase. The requirements are about identifying and documenting findings, not about runtime behavior. The "tests" are the systematic analysis itself, not executable test suites.

### Sampling Rate
- **Per task commit:** Visual review of findings document completeness
- **Per wave merge:** Cross-reference findings against contract list (all 34 covered?)
- **Phase gate:** All 4 requirements addressed with documented evidence

### Wave 0 Gaps
None -- existing test infrastructure is irrelevant to this audit-only phase. No new test files needed.

## Open Questions

1. **Boon packing -- is it worth documenting every pair?**
   - What we know: There are ~10 pairs of boon active+day mappings that could theoretically be packed
   - What's unclear: Whether the protocol team intends to redeploy (packing requires it)
   - Recommendation: Document the PATTERN once with one concrete example and estimated savings, note that it applies to all similar pairs. Don't enumerate every pair individually.

2. **Slither dead-code results accuracy**
   - What we know: The slither config in package.json explicitly excludes `dead-code` from its detector list
   - What's unclear: Whether dead-code was excluded because it produced false positives on this codebase
   - Recommendation: Run slither with dead-code enabled once for informational purposes, but verify every finding manually before reporting.

## Sources

### Primary (HIGH confidence)
- `forge inspect DegenerusGameStorage storageLayout` -- verified storage layout, 110 slots (0-109)
- `contracts/storage/DegenerusGameStorage.sol` -- 1,599 lines, full variable documentation
- v3.3 Phase 47 gas analysis (git commit `d624b4cc`) -- 7 sDGNRS variables ALIVE, 3 packing opportunities

### Secondary (MEDIUM confidence)
- [Solidity Optimizer Documentation](https://docs.soliditylang.org/en/latest/internals/optimizer.html)
- [RareSkills Gas Optimization Guide](https://rareskills.io/post/gas-optimization)

### Tertiary (LOW confidence)
- None

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - forge inspect and slither are verified available and working
- Architecture: HIGH - full storage layout extracted and verified via compiler
- Pitfalls: HIGH - based on direct codebase analysis and prior phase experience (v3.3 Phase 47)

**Research date:** 2026-03-21
**Valid until:** 2026-04-21 (stable codebase, 30 days)
