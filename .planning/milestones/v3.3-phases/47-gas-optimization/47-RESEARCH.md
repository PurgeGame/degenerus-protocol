# Phase 47: Gas Optimization - Research

**Researched:** 2026-03-20
**Domain:** Solidity storage layout optimization and gas benchmarking for sDGNRS gambling burn system
**Confidence:** HIGH

## Summary

This phase targets gas optimization of the 7 new state variables added to StakedDegenerusStonk.sol for the gambling burn / redemption system. The work decomposes into four requirements: confirming each variable is actually needed (GAS-01), identifying storage packing opportunities (GAS-02), establishing a Forge snapshot gas baseline (GAS-03), and eliminating any dead variables found (GAS-04).

The 7 new state variables occupy storage slots 9-15 in the sDGNRS contract. Every variable has at least one write and one read path in the gambling burn lifecycle, making elimination unlikely. However, significant storage packing opportunities exist: slot 14 contains only `redemptionPeriodIndex` (uint48, 6 bytes), wasting 26 bytes. Several uint256 variables can be safely narrowed to uint128 since token supply is 1T * 1e18 = ~100 bits and ETH reserves are bounded at ~87 bits. The `PendingRedemption` struct also wastes a full slot for `periodIndex` (uint48) that could pack with the two owed values if narrowed to uint128.

**Primary recommendation:** Execute variable-by-variable liveness analysis first (GAS-01), then analyze packing opportunities with concrete gas savings (GAS-02), build a Foundry gas snapshot test for all redemption functions (GAS-03), and finally implement any removals or packings that save > 1000 gas per call (GAS-04). The Foundry snapshot must work around the existing compilation error in `QueueDoubleBuffer.t.sol` by using `--match-path` filtering.

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| GAS-01 | Dead variable check -- confirm all 7 new state variables in sDGNRS are actually needed | Storage layout inspection shows 7 variables (slots 9-15). Each variable's read/write sites are documented below with cross-references. All 7 appear actively used in the submit/resolve/claim lifecycle. |
| GAS-02 | Storage packing analysis -- identify packing opportunities (e.g., redemptionPeriodIndex uint48) | Slot 14 has 26 bytes free. pendingRedemptionEthBase + pendingRedemptionBurnieBase could pack as uint128+uint128. PendingRedemption struct could save 1 slot per user by packing ethValueOwed+burnieOwed as uint128. Detailed analysis with bit-width proofs below. |
| GAS-03 | Gas snapshot baseline -- forge snapshot for all redemption functions | `forge snapshot` is available. Foundry tests exist in `test/fuzz/` but no gambling burn tests exist yet. A new Foundry test file is needed that exercises burn(), burnWrapped(), claimRedemption(), resolveRedemptionPeriod(), and hasPendingRedemptions(). Must use `--match-path` to exclude broken `QueueDoubleBuffer.t.sol`. |
| GAS-04 | Unneeded variable elimination -- implement removals identified by GAS-01 | Unlikely to find dead variables (all 7 are actively used). If GAS-01 finds any, removal is straightforward: delete declaration, remove all read/write sites, verify `forge build --skip test` compiles, verify `npm run test:unit` passes. |
</phase_requirements>

## Standard Stack

### Core
| Tool | Version | Purpose | Why Standard |
|------|---------|---------|--------------|
| Foundry (forge) | v1.0+ | Gas snapshot, test compilation, storage layout inspection | Already installed, `foundry.toml` configured with `via_ir = true`, `optimizer_runs = 2` |
| Solidity | 0.8.34 | Source language | Project compiler version |
| Hardhat | (project version) | Unit test runner for regression verification | Existing test suite (698 lines in DegenerusStonk.test.js) |

### Supporting
| Tool | Purpose | When to Use |
|------|---------|-------------|
| `forge inspect StakedDegenerusStonk storageLayout` | Verify storage slot assignments after packing changes | After any struct or variable type changes |
| `forge snapshot` | Generate gas baseline for all redemption functions | After creating Foundry test file for gambling burn paths |
| `forge test --gas-report` | Detailed per-function gas analysis | To quantify savings from packing changes |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Foundry gas snapshot | Hardhat gas reporter | Foundry is more precise and already configured; Hardhat reporter adds noise from JS overhead |
| Manual storage inspection | Slither `contract-summary` | Slither provides more automated analysis but adds dependency; `forge inspect` is sufficient |

## Architecture Patterns

### Current Storage Layout (StakedDegenerusStonk)

```
Slot  Variable                          Type      Bytes  Wasted
----  --------                          ----      -----  ------
0     totalSupply                       uint256   32     0
1     balanceOf                         mapping   32     0
2-6   poolBalances[5]                   uint256[] 160    0
7     pendingRedemptions                mapping   32     0
8     redemptionPeriods                 mapping   32     0
9     pendingRedemptionEthValue         uint256   32     0      <-- NEW
10    pendingRedemptionBurnie           uint256   32     0      <-- NEW
11    pendingRedemptionEthBase          uint256   32     0      <-- NEW
12    pendingRedemptionBurnieBase       uint256   32     0      <-- NEW
13    redemptionPeriodSupplySnapshot    uint256   32     0      <-- NEW
14    redemptionPeriodIndex             uint48    6      26     <-- NEW (26 bytes wasted!)
15    redemptionPeriodBurned            uint256   32     0      <-- NEW
```

### PendingRedemption Struct Layout (per-user, in mapping slot 7)
```
Struct Slot  Field           Type      Bytes  Wasted
-----------  -----           ----      -----  ------
0            ethValueOwed    uint256   32     0
1            burnieOwed      uint256   32     0
2            periodIndex     uint48    6      26     (26 bytes wasted!)
```

### RedemptionPeriod Struct Layout (per-period, in mapping slot 8)
```
Struct Slot  Field     Type    Bytes  Wasted
-----------  -----     ----    -----  ------
0            roll      uint16  2      0
0            flipDay   uint48  6      24     (already packed in 1 slot -- good)
```

### Variable Liveness Analysis (GAS-01 Pre-Research)

All 7 variables have been traced through the gambling burn lifecycle:

| Variable | Write Sites | Read Sites | Verdict |
|----------|------------|------------|---------|
| `pendingRedemptionEthValue` | `_submitGamblingClaimFrom:712`, `resolveRedemptionPeriod:553` | `hasPendingRedemptions`: no, `resolveRedemptionPeriod:553`, `claimRedemption:599`, `previewBurn:633,637,638`, `_submitGamblingClaimFrom:695` | ALIVE -- segregation accounting for ETH |
| `pendingRedemptionBurnie` | `_submitGamblingClaimFrom:714`, `resolveRedemptionPeriod:560` | `previewBurn:651`, `burnieReserve:661`, `_submitGamblingClaimFrom:701` | ALIVE -- segregation accounting for BURNIE |
| `pendingRedemptionEthBase` | `_submitGamblingClaimFrom:713`, `resolveRedemptionPeriod:554` | `hasPendingRedemptions:537`, `resolveRedemptionPeriod:549,552` | ALIVE -- current unresolved period ETH accumulator |
| `pendingRedemptionBurnieBase` | `_submitGamblingClaimFrom:715`, `resolveRedemptionPeriod:561` | `hasPendingRedemptions:537`, `resolveRedemptionPeriod:549,557` | ALIVE -- current unresolved period BURNIE accumulator |
| `redemptionPeriodSupplySnapshot` | `_submitGamblingClaimFrom:682` | `_submitGamblingClaimFrom:686` | ALIVE -- 50% supply cap enforcement |
| `redemptionPeriodIndex` | `_submitGamblingClaimFrom:683` | `_submitGamblingClaimFrom:681`, `resolveRedemptionPeriod:548` | ALIVE -- period boundary tracking |
| `redemptionPeriodBurned` | `_submitGamblingClaimFrom:684,687` | `_submitGamblingClaimFrom:686` | ALIVE -- burned-this-period accumulator |

**Preliminary finding: All 7 variables are actively used. No dead variables expected.** GAS-01 should formalize this with explicit write/read/delete traces for each variable, but elimination is unlikely.

### Storage Packing Opportunities (GAS-02 Pre-Research)

#### Opportunity 1: Pack `redemptionPeriodIndex` + `redemptionPeriodBurned` (save 1 slot)

**Current:** Slot 14 = `redemptionPeriodIndex` (uint48, 6 bytes), Slot 15 = `redemptionPeriodBurned` (uint256, 32 bytes)

**Proposed:** Slot 14 = `redemptionPeriodIndex` (uint48) + `redemptionPeriodBurned` (uint208)

**Safety proof:** `redemptionPeriodBurned` max = `totalSupply / 2` = 500e27. `uint208` max = 2^208 = ~4.1e62. Value fits with 100+ bits of headroom.

**Gas savings:** Eliminates 1 SSTORE (20,000 gas cold / 5,000 warm) on the first `_submitGamblingClaimFrom` call per period (where both are written together at lines 682-684). Also eliminates 1 SLOAD (2,100 cold / 100 warm) on subsequent calls within the same period (where both are read together at line 686).

**Risk:** LOW. Both variables are always read and written together in `_submitGamblingClaimFrom`. No external read interface for `redemptionPeriodBurned`.

#### Opportunity 2: Pack `pendingRedemptionEthBase` + `pendingRedemptionBurnieBase` (save 1 slot)

**Current:** Slot 11 = `pendingRedemptionEthBase` (uint256), Slot 12 = `pendingRedemptionBurnieBase` (uint256)

**Proposed:** Single slot = `pendingRedemptionEthBase` (uint128) + `pendingRedemptionBurnieBase` (uint128)

**Safety proof:** `pendingRedemptionEthBase` is bounded by `ethBal + stethBal + claimableEth` which realistically caps at ~100K ETH (87 bits). `pendingRedemptionBurnieBase` is bounded by total BURNIE supply (100 bits max). Both fit in uint128 (128 bits) with comfortable margins.

**Gas savings:** These two are always read and written together in `hasPendingRedemptions` (line 537), `resolveRedemptionPeriod` (lines 549-561), and `_submitGamblingClaimFrom` (lines 713-715). Packing saves 1 SLOAD + 1 SSTORE per call to each function.

**Risk:** LOW-MEDIUM. uint128 is safe for realistic values. The theoretical max for BURNIE base is ~100 bits, well within uint128's 128-bit capacity. However, if BURNIE supply is ever increased beyond 2^128, this would silently truncate. This is an immutable contract with fixed INITIAL_SUPPLY so the risk is negligible.

#### Opportunity 3: Pack `PendingRedemption` struct (save 1 slot per user)

**Current:** 3 slots per user (ethValueOwed uint256, burnieOwed uint256, periodIndex uint48)

**Proposed:** 2 slots (ethValueOwed uint128 + burnieOwed uint128 in slot 0, periodIndex uint48 in slot 1)

**Safety proof:** Same bit-width analysis as Opportunity 2. ethValueOwed bounded by realistic ETH pool (~87 bits), burnieOwed bounded by BURNIE supply (~100 bits).

**Gas savings:** Saves 1 SLOAD on `claimRedemption` read and 1 SSTORE on `_submitGamblingClaimFrom` write. For per-user operations this is meaningful.

**Risk:** LOW-MEDIUM. Same uint128 truncation risk as above. Additionally, `ethValueOwed` and `burnieOwed` use `+=` in `_submitGamblingClaimFrom:722-723`, so the packed write requires masking arithmetic which adds ~20 gas but saves ~5000 gas from the eliminated slot access.

#### Opportunity 4: Pack `redemptionPeriodSupplySnapshot` (uint256 -> uint208) into slot with `redemptionPeriodIndex`

**Not recommended.** `redemptionPeriodSupplySnapshot` is already read/written in the same function as `redemptionPeriodIndex` and `redemptionPeriodBurned`. Packing all three into one slot would require: uint48 + uint104 + uint104 = 256 bits. But `redemptionPeriodBurned` max is 100 bits and `redemptionPeriodSupplySnapshot` max is 100 bits, so uint104 is tight. Better to pack index+burned (Opportunity 1) and leave supplySnapshot as uint256 for safety.

### Estimated Total Gas Savings

| Opportunity | Cold Path Savings | Warm Path Savings | Risk |
|-------------|-------------------|-------------------|------|
| 1: Pack index+burned | ~22,100 gas (1 SSTORE + 1 SLOAD) | ~5,100 gas | LOW |
| 2: Pack ethBase+burnieBase | ~22,100 gas per fn call | ~5,100 gas | LOW-MEDIUM |
| 3: Pack PendingRedemption struct | ~22,100 gas per user op | ~5,100 gas | LOW-MEDIUM |
| **Total per gambling burn** | **~44,200-66,300 gas** | **~10,200-15,300 gas** | -- |

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Storage layout inspection | Manual slot counting | `forge inspect storageLayout` | Compiler output is authoritative; manual counting is error-prone with mappings and structs |
| Gas benchmarking | Console.log timing | `forge snapshot` / `forge test --gas-report` | Built into Foundry, produces deterministic gas counts |
| Bit-width overflow checking | Manual math | `python3` or `chisel` REPL | Compute max values precisely; don't rely on estimates |

## Common Pitfalls

### Pitfall 1: Breaking the Optimizer with Packing

**What goes wrong:** Packing variables into smaller types can paradoxically increase gas if the compiler generates additional masking/shifting operations that aren't offset by the SLOAD/SSTORE savings.

**Why it happens:** Solidity 0.8.x with `via_ir = true` and `optimizer_runs = 2` (as configured in this project's foundry.toml) optimizes for deployment size, not runtime gas. Low optimizer_runs means the compiler does NOT aggressively inline or optimize storage access patterns.

**How to avoid:** Measure gas before AND after packing with `forge snapshot`. If a packed version costs more gas at runtime, revert it. The snapshot diff is the authoritative source.

**Warning signs:** Gas increase > 500 in any function after packing.

### Pitfall 2: Forge Snapshot Compilation Failures

**What goes wrong:** `forge snapshot` compiles ALL test files, and `test/fuzz/QueueDoubleBuffer.t.sol` has a pre-existing compilation error (`MID_DAY_SWAP_THRESHOLD` undeclared).

**Why it happens:** The `foundry.toml` sets `test = "test/fuzz"`, so all `.t.sol` files in that directory are compiled.

**How to avoid:** Use `--match-path` or `--match-contract` to scope the snapshot run to only the gas benchmark test file. Alternatively, create the new gas test in a directory that can be compiled independently.

**Warning signs:** `Error (7576): Undeclared identifier` during snapshot runs.

### Pitfall 3: Packing Breaks `delete` Semantics

**What goes wrong:** The `delete pendingRedemptions[player]` at line 602 in `claimRedemption()` must zero out the entire struct. With packed structs, `delete` still works correctly in Solidity -- it zeros all fields. But if you manually implement packing via assembly, you must handle deletion yourself.

**Why it happens:** Mixing Solidity-level struct deletion with assembly-level packing.

**How to avoid:** Use Solidity's native struct packing (just change field types) rather than assembly. `delete` will work correctly.

**Warning signs:** Leftover non-zero bits after deletion in packed slots.

### Pitfall 4: uint128 Overflow in Accumulation

**What goes wrong:** `pendingRedemptionEthBase += ethValueOwed` (line 713) accumulates across multiple burns in the same period. If many users burn in the same period, the accumulator could theoretically exceed uint128.

**Why it happens:** Single-user burns are bounded, but the accumulator sums across all users.

**How to avoid:** The 50% supply cap per period (line 686) bounds total burns. Max ethValueOwed per period = (totalMoney * totalSupply/2) / totalSupply = totalMoney / 2. For ETH, this is half of all contract holdings, which is well within uint128. Document this proof in code comments.

**Warning signs:** Total contract ETH holdings approaching 2^128 wei (~3.4e38 wei = 3.4e20 ETH) -- impossible in practice.

### Pitfall 5: Gas Snapshot Without Gambling Burn Tests

**What goes wrong:** GAS-03 requires a forge snapshot for all redemption functions, but no Foundry tests exercise the gambling burn path. The existing `.gas-snapshot` file only covers AdvanceGameRewrite, BurnieCoinInvariants, DustAccumulation, and FreezeLifecycle tests.

**Why it happens:** Gambling burn tests only exist in the Hardhat suite (test/unit/DegenerusStonk.test.js), and even there they only test the deterministic (post-gameOver) burn path, not the gambling path.

**How to avoid:** Write a new Foundry test file (e.g., `test/fuzz/RedemptionGas.t.sol`) that exercises all redemption functions: `burn()`, `burnWrapped()`, `_submitGamblingClaimFrom()` (via `burn()` during active game), `resolveRedemptionPeriod()`, `claimRedemption()`, `hasPendingRedemptions()`, and `previewBurn()`.

**Warning signs:** Empty or missing gas entries in the snapshot file for redemption functions.

## Code Examples

### Packing redemptionPeriodIndex + redemptionPeriodBurned

```solidity
// BEFORE: 2 storage slots
uint48  internal redemptionPeriodIndex;    // slot 14 (6 bytes, 26 wasted)
uint256 internal redemptionPeriodBurned;   // slot 15 (32 bytes)

// AFTER: 1 storage slot
uint48  internal redemptionPeriodIndex;    // slot 14, offset 0, 6 bytes
uint208 internal redemptionPeriodBurned;   // slot 14, offset 6, 26 bytes
// uint208 max = 4.1e62, max burned per period = 5e29, fits with 162 bits headroom
```

### Packing pendingRedemptionEthBase + pendingRedemptionBurnieBase

```solidity
// BEFORE: 2 storage slots (slots 11-12)
uint256 internal pendingRedemptionEthBase;
uint256 internal pendingRedemptionBurnieBase;

// AFTER: 1 storage slot
uint128 internal pendingRedemptionEthBase;     // max realistic ~1e23 (87 bits)
uint128 internal pendingRedemptionBurnieBase;  // max realistic ~1e30 (100 bits)
// Both fit in uint128 (128 bits) with comfortable margins
```

### Packing PendingRedemption struct

```solidity
// BEFORE: 3 storage slots per user
struct PendingRedemption {
    uint256 ethValueOwed;   // 32 bytes
    uint256 burnieOwed;     // 32 bytes
    uint48  periodIndex;    // 6 bytes (26 wasted)
}

// AFTER: 2 storage slots per user
struct PendingRedemption {
    uint128 ethValueOwed;   // 16 bytes \
    uint128 burnieOwed;     // 16 bytes  > packed in slot 0
    uint48  periodIndex;    // 6 bytes, slot 1 (26 wasted, but saves 1 slot vs before)
}
```

### Forge Snapshot Test Skeleton

```solidity
// test/fuzz/RedemptionGas.t.sol
// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {Test} from "forge-std/Test.sol";

// Minimal interfaces needed for gas measurement
// Deploy or mock the full protocol, then:

contract RedemptionGasTest is Test {
    function test_gas_burn_gambling() external {
        // Setup: give player sDGNRS, ensure game is active (not gameOver)
        // Measure: sdgnrs.burn(amount)
    }

    function test_gas_resolveRedemptionPeriod() external {
        // Setup: submit a gambling claim, then call as game contract
        // Measure: sdgnrs.resolveRedemptionPeriod(roll, flipDay)
    }

    function test_gas_claimRedemption() external {
        // Setup: submit claim, resolve period, resolve coinflip
        // Measure: sdgnrs.claimRedemption()
    }

    function test_gas_hasPendingRedemptions_true() external {
        // Setup: submit a claim
        // Measure: sdgnrs.hasPendingRedemptions()
    }

    function test_gas_hasPendingRedemptions_false() external {
        // Setup: no claims
        // Measure: sdgnrs.hasPendingRedemptions()
    }

    function test_gas_previewBurn_withPending() external view {
        // Measure: sdgnrs.previewBurn(amount) with pending redemptions
    }
}
```

### Running Forge Snapshot (avoiding compilation error)

```bash
# Targeted snapshot for redemption gas tests only
forge snapshot --match-path "test/fuzz/RedemptionGas.t.sol" --snap .gas-snapshot-redemption

# Compare before/after packing changes
forge snapshot --match-path "test/fuzz/RedemptionGas.t.sol" --diff .gas-snapshot-redemption
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Manual gas estimation | `forge snapshot --diff` | Foundry v0.2+ | Deterministic before/after comparison |
| Assembly storage packing | Solidity native type narrowing | Solidity 0.8.x | Compiler handles packing; assembly is error-prone and unnecessary |
| Separate cold/warm benchmarks | `forge test --gas-report` | Foundry v1.0 | Reports min/avg/max gas per function automatically |

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Foundry (forge) v1.0 + Hardhat (existing unit tests) |
| Config file | `foundry.toml` (test path: `test/fuzz/`) |
| Quick run command | `forge test --match-path "test/fuzz/RedemptionGas.t.sol" -vvv` |
| Full suite command | `npm run test:unit && forge test --match-path "test/fuzz/RedemptionGas.t.sol"` |

### Phase Requirements -> Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| GAS-01 | All 7 variables confirmed alive or dead | manual analysis | N/A (code reading, not testing) | N/A |
| GAS-02 | Storage packing documented with savings | manual + `forge inspect` | `forge inspect StakedDegenerusStonk storageLayout` | N/A |
| GAS-03 | Gas snapshot baseline exists | forge snapshot | `forge snapshot --match-path "test/fuzz/RedemptionGas.t.sol"` | Wave 0 (must create) |
| GAS-04 | Dead variables removed, tests pass | unit + integration | `npm run test:unit && forge build --skip test` | Existing (DegenerusStonk.test.js) |

### Sampling Rate
- **Per task commit:** `forge build --skip test` (compilation check)
- **Per wave merge:** `npm run test:unit` (regression check)
- **Phase gate:** `forge snapshot --match-path "test/fuzz/RedemptionGas.t.sol" --diff .gas-snapshot-redemption` (gas regression check)

### Wave 0 Gaps
- [ ] `test/fuzz/RedemptionGas.t.sol` -- Foundry gas benchmark test for all redemption functions (GAS-03)
- [ ] Gambling burn test infrastructure -- no existing Foundry or Hardhat tests exercise the full gambling burn lifecycle (submit -> resolve -> claim)

## Open Questions

1. **Forge snapshot vs broken test file**
   - What we know: `QueueDoubleBuffer.t.sol` has a compilation error. `forge snapshot` without filtering will fail.
   - What's unclear: Whether the broken file can be fixed without scope creep (it references `MID_DAY_SWAP_THRESHOLD` which may have been renamed/removed).
   - Recommendation: Use `--match-path` filtering to exclude it. Do NOT fix the broken test (out of scope for this phase).

2. **Packing implementation order**
   - What we know: Three packing opportunities exist with varying risk levels.
   - What's unclear: Whether all three should be implemented or just the lowest-risk ones.
   - Recommendation: Implement Opportunity 1 (index+burned, LOW risk) first. Then Opportunity 2 (ethBase+burnieBase, LOW-MEDIUM risk). Opportunity 3 (struct packing) is most impactful but highest risk; implement last and only if snapshot confirms savings.

3. **Gas test complexity**
   - What we know: Writing a Foundry gas test for gambling burn requires deploying the full protocol (4+ contracts with cross-contract dependencies).
   - What's unclear: Whether the existing Foundry test helpers support full protocol deployment or if only Hardhat fixtures do.
   - Recommendation: Check `test/fuzz/helpers/` for existing deploy infrastructure. If none exists, use `vm.etch` + `vm.store` to mock contract state rather than deploying the full protocol. Gas measurements of isolated functions are sufficient for baseline.

## Sources

### Primary (HIGH confidence)
- `forge inspect StakedDegenerusStonk storageLayout` -- authoritative storage slot assignments from compiler
- `contracts/StakedDegenerusStonk.sol` lines 179-200 -- all 7 new state variable declarations
- `contracts/StakedDegenerusStonk.sol` lines 530-727 -- all read/write sites for liveness analysis
- `foundry.toml` -- project configuration (via_ir=true, optimizer_runs=2, test path=test/fuzz)
- `.gas-snapshot` -- existing gas baseline (30 entries, no redemption functions)

### Secondary (MEDIUM confidence)
- Phase 44 research (44-RESEARCH.md) -- architecture patterns, lifecycle flow
- Phase 44 finding verdicts (44-01-finding-verdicts.md) -- CP-08 confirmed, code has pending fixes

### Tertiary (LOW confidence)
- Gas savings estimates are theoretical (20,000 gas per cold SSTORE, 5,000 warm). Actual savings depend on EVM opcode pricing which may change in future hard forks. Forge snapshot will give actual numbers.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH -- Foundry + Hardhat already configured and used throughout project
- Architecture: HIGH -- storage layout verified via `forge inspect`, variable liveness traced through source code
- Pitfalls: HIGH -- compilation error verified, packing semantics well-understood for Solidity 0.8.x
- Gas estimates: MEDIUM -- theoretical based on EVM opcode costs; will be confirmed by forge snapshot

**Research date:** 2026-03-20
**Valid until:** 2026-04-20 (stable domain -- Solidity gas semantics rarely change)
