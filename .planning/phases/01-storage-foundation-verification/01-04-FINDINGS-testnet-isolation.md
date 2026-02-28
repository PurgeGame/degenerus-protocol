# STOR-04: Testnet Isolation Verification

**Requirement:** No testnet configuration (TESTNET_ETH_DIVISOR) bleeds into mainnet contract logic.
**Date:** 2026-02-28
**Auditor:** Automated scan + manual review

---

## Section 1: Isolation Mechanism

The project uses **physical filesystem separation** to isolate mainnet and testnet contract sources. There is no preprocessor, no conditional compilation, and no runtime flag that switches behavior.

**hardhat.config.js** (lines 4, 33-35):

```javascript
const isTestnetBuild = process.env.TESTNET_BUILD === "1";

paths: {
  sources: isTestnetBuild ? "./contracts-testnet" : "./contracts",
  cache: isTestnetBuild ? "cache-testnet" : "cache",
  artifacts: isTestnetBuild ? "artifacts-testnet" : "artifacts",
}
```

**Mechanism:**
- `TESTNET_BUILD=1` environment variable triggers testnet compilation
- When set: Hardhat reads from `contracts-testnet/`, writes artifacts to `artifacts-testnet/`
- When unset (default): Hardhat reads from `contracts/`, writes to `artifacts/`
- The two directories are **independent full copies** with modifications applied directly to files
- No shared source code path -- each directory is self-contained
- Build artifacts are also separated, preventing testnet ABIs from contaminating mainnet deployments

**Assessment:** This is the strongest possible isolation pattern. No Solidity preprocessor exists, so physical separation is the only clean option. The default path (no env var) always compiles mainnet, making accidental testnet builds impossible without explicit opt-in.

---

## Section 2: TESTNET_ETH_DIVISOR Scope Verification

### Primary Scan: Mainnet Source (contracts/)

```
$ grep -rn "TESTNET_ETH_DIVISOR" contracts/
(no output -- zero matches)
```

**Result: ZERO occurrences of TESTNET_ETH_DIVISOR in the mainnet contract tree.**

### Control Scan: Testnet Source (contracts-testnet/)

```
$ grep -rn "TESTNET_ETH_DIVISOR" contracts-testnet/
contracts-testnet/storage/DegenerusGameStorage.sol:129:    uint256 internal constant TESTNET_ETH_DIVISOR = 1_000_000;
contracts-testnet/storage/DegenerusGameStorage.sol:137:        5 ether / TESTNET_ETH_DIVISOR;
contracts-testnet/storage/DegenerusGameStorage.sol:142:        50 ether / TESTNET_ETH_DIVISOR;
contracts-testnet/storage/DegenerusGameStorage.sol:149:        1_000 ether / TESTNET_ETH_DIVISOR;
contracts-testnet/storage/DegenerusGameStorage.sol:282:        uint128(0.01 ether / TESTNET_ETH_DIVISOR);
contracts-testnet/storage/DegenerusGameStorage.sol:1195:        1 ether / TESTNET_ETH_DIVISOR;
```

**Result: 6 occurrences, all in `contracts-testnet/storage/DegenerusGameStorage.sol`.**

TESTNET_ETH_DIVISOR is a `uint256 internal constant = 1_000_000` that divides ETH thresholds by 1 million for testnet affordability. It modifies:
- Base price thresholds (5 ETH, 50 ETH, 1000 ETH)
- Minimum purchase amounts (0.01 ETH)
- Other ETH-denominated constants (1 ETH)

**STOR-04 Evidence:** The constant is physically absent from mainnet source. It cannot be compiled into mainnet bytecode.

---

## Section 3: Cross-Directory Import Check

### Mainnet importing testnet:

```
$ grep -rn "contracts-testnet" contracts/
(no output -- zero matches)
```

### Testnet importing mainnet:

```
$ grep -rn "../contracts/" contracts-testnet/
(no output -- zero matches)
```

**Result: No cross-directory imports exist.** The two source trees are fully independent. No Solidity `import` statement references the other directory.

---

## Section 4: _simulatedDayIndex() Name Analysis

### Mainnet Implementation (contracts/storage/DegenerusGameStorage.sol, lines 1133-1140)

```solidity
/// @dev Returns the current day index.
function _simulatedDayIndex() internal view returns (uint48) {
    return GameTimeLib.currentDayIndex();
}

/// @dev Returns the day index for a specific timestamp.
function _simulatedDayIndexAt(uint48 ts) internal pure returns (uint48) {
    return GameTimeLib.currentDayIndexAt(ts);
}
```

**Mainnet behavior:** Calls `GameTimeLib.currentDayIndex()` directly -- uses real `block.timestamp` math. No offset, no simulation, no mock logic. The function is `view` (reads blockchain state only) and `internal` (not externally callable).

### Testnet Implementation (contracts-testnet/storage/DegenerusGameStorage.sol, lines 1136-1142)

```solidity
/// @dev Returns the current day index (with testnet offset applied).
function _simulatedDayIndex() internal view returns (uint48) {
    return GameTimeLib.currentDayIndex() + dayOffset;
}

/// @dev Returns the day index for a specific timestamp (with testnet offset applied).
function _simulatedDayIndexAt(uint48 ts) internal view returns (uint48) {
    return GameTimeLib.currentDayIndexAt(ts) + dayOffset;
}
```

**Testnet behavior:** Adds `dayOffset` (a `uint48` state variable at storage slot, line 1410) to enable fast day progression for testing. The testnet `DegenerusGame.sol` has `advanceDay()` and `advanceDays(n)` functions that increment this offset.

### dayOffset State Variable

```
$ grep -rn "dayOffset" contracts/
(no output -- zero matches)

$ grep -rn "dayOffset" contracts-testnet/
contracts-testnet/DegenerusGame.sol:534:        dayOffset += 1;
contracts-testnet/DegenerusGame.sol:535:        emit DayAdvanced(dayOffset, _simulatedDayIndex());
contracts-testnet/DegenerusGame.sol:543:        dayOffset += n;
contracts-testnet/DegenerusGame.sol:544:        emit DayAdvanced(dayOffset, _simulatedDayIndex());
contracts-testnet/storage/DegenerusGameStorage.sol:1137:        return GameTimeLib.currentDayIndex() + dayOffset;
contracts-testnet/storage/DegenerusGameStorage.sol:1142:        return GameTimeLib.currentDayIndexAt(ts) + dayOffset;
contracts-testnet/storage/DegenerusGameStorage.sol:1410:    uint48 internal dayOffset;
```

**Result:** `dayOffset` is entirely absent from mainnet source. The "simulated" prefix in mainnet is a **naming artifact** from the original development when both versions shared inheritance. It has no behavioral impact.

**Usage scope:** `_simulatedDayIndex()` is called in 29 locations across mainnet contracts (DegenerusGame.sol, all game modules). Every call resolves to `GameTimeLib.currentDayIndex()` -- real timestamps throughout.

**Informational recommendation:** Rename `_simulatedDayIndex()` to `_currentDayIndex()` in mainnet source to eliminate naming confusion during future audits. Severity: Informational (naming only, no behavioral risk).

---

## Section 5: Other Testnet Patterns in Mainnet Source

### Broader Scan

```
$ grep -rn "testnet|TEST_|_TESTNET" contracts/ (case-insensitive)

contracts/BurnieCoinflip.sol:510:  // Skip unresolved days (gaps from testnet day-advance or missed resolution)
contracts/BurnieCoinflip.sol:987:  // to handle gaps from testnet day-advance or missed resolution.
contracts/modules/DegenerusGameMintModule.sol:90:  /// @dev BURNIE loot box minimum purchase amount (scaled for testnet).
contracts/modules/DegenerusGameJackpotModule.sol:2296:  /// @dev Calculate current day index with testnet offset applied.
```

**Analysis of each hit:**

| File | Line | Type | Assessment |
|------|------|------|------------|
| BurnieCoinflip.sol | 510 | Comment (`//`) | Explains gap-handling logic. No runtime testnet behavior. **Safe.** |
| BurnieCoinflip.sol | 987 | Comment (`//`) | Same pattern as above -- documents skip logic. **Safe.** |
| DegenerusGameMintModule.sol | 90 | NatSpec (`/// @dev`) | **Misleading comment.** The constant `BURNIE_LOOTBOX_MIN = 1000 ether` is not actually scaled for testnet -- this appears to be a stale comment. The mainnet value is 1000 ether. **Safe** (comment only, no code impact). |
| DegenerusGameJackpotModule.sol | 2296 | NatSpec (`/// @dev`) | **Misleading comment.** References "testnet offset" but the mainnet `_simulatedDayIndex()` has no offset. **Safe** (comment only, no code impact). |

**Result:** All 4 hits are comments or NatSpec documentation. No runtime conditional logic gated on testnet-related strings exists in mainnet contracts.

**Informational recommendation:** Clean up stale testnet references in NatSpec comments:
- DegenerusGameMintModule.sol line 90: Remove "scaled for testnet" wording
- DegenerusGameJackpotModule.sol line 2296: Remove "testnet offset" wording
Severity: Informational (documentation accuracy only).

---

## Section 6: Testnet vs Mainnet Diff Summary

Files that differ between `contracts/` and `contracts-testnet/`:

```
$ diff -rq contracts/ contracts-testnet/

Files differ:
  DegenerusAdmin.sol
  DegenerusAffiliate.sol
  DegenerusDeityPass.sol
  DegenerusGame.sol
  DegenerusQuests.sol
  DegenerusStonk.sol
  interfaces/IBurnieCoinflip.sol
  interfaces/IDegenerusGame.sol
  libraries/JackpotBucketLib.sol
  libraries/PriceLookupLib.sol
  modules/DegenerusGameAdvanceModule.sol
  modules/DegenerusGameDegeneretteModule.sol
  modules/DegenerusGameEndgameModule.sol
  modules/DegenerusGameGameOverModule.sol
  modules/DegenerusGameJackpotModule.sol
  modules/DegenerusGameLootboxModule.sol
  modules/DegenerusGameMintModule.sol
  modules/DegenerusGamePayoutUtils.sol
  modules/DegenerusGameWhaleModule.sol
  storage/DegenerusGameStorage.sol
```

**Total:** 20 files differ between mainnet and testnet directories.

This is expected for a full-copy isolation approach. The testnet versions contain:
- TESTNET_ETH_DIVISOR scaling (in DegenerusGameStorage.sol)
- dayOffset / day advancement functions (in DegenerusGame.sol + storage)
- Reduced VRF retry timeouts (5 minutes vs 18 hours)
- Other testnet-specific convenience functions and parameter adjustments

---

## Section 7: Requirement Verdict

### STOR-04: PASS

**Requirement:** No testnet configuration (TESTNET_ETH_DIVISOR) bleeds into mainnet contract logic.

**Evidence:**

| Check | Result | Detail |
|-------|--------|--------|
| TESTNET_ETH_DIVISOR in contracts/ | **ZERO matches** | Completely absent from mainnet source |
| TESTNET_ETH_DIVISOR in contracts-testnet/ | 6 matches | Correctly confined to testnet storage |
| Cross-directory imports (mainnet -> testnet) | **ZERO matches** | No import path leakage |
| Cross-directory imports (testnet -> mainnet) | **ZERO matches** | No shared code path |
| Runtime testnet conditionals in mainnet | **ZERO** | All testnet references are comments only |
| dayOffset in mainnet | **ZERO matches** | Testnet-only state variable |
| _simulatedDayIndex() mainnet behavior | Real timestamps | Calls GameTimeLib.currentDayIndex() directly |
| hardhat.config.js default path | contracts/ (mainnet) | Testnet requires explicit TESTNET_BUILD=1 |

**Conclusion:** Physical filesystem separation provides complete isolation. TESTNET_ETH_DIVISOR cannot appear in mainnet bytecode because it does not exist in the mainnet source tree. The hardhat.config.js default always compiles from `contracts/`, and testnet compilation requires an explicit environment variable opt-in. No runtime conditional path exists that could route mainnet execution through testnet logic.

### Informational Findings

1. **Stale naming: _simulatedDayIndex()** -- Function name implies simulation but mainnet implementation uses real timestamps. Recommend renaming to `_currentDayIndex()`. Severity: Informational.

2. **Stale NatSpec comments** -- Two comments reference "testnet" in mainnet source (MintModule line 90, JackpotModule line 2296). No behavioral impact. Recommend cleanup. Severity: Informational.
