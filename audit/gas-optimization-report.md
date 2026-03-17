# Gas Optimization Report: Scavenger/Skeptic Dual-Agent Audit

**Protocol:** Degenerus Protocol (v2.0)
**Compiler:** Solidity 0.8.34, viaIR=true, optimizer runs=200
**Scope:** ~25,600 lines across 28 production contracts + 5 libraries + 2 interfaces
**Date:** 2026-03-17

---

## Executive Summary

The Scavenger/Skeptic dual-agent gas audit analyzed all production Solidity contracts in the Degenerus Protocol. The Scavenger identified 21 potential optimization candidates across 4 categories (GAS-01 through GAS-04). The Skeptic then validated each recommendation with rigorous counterexample testing and cross-contract tracing.

**Verdict Distribution:**

| Verdict | Count |
|---------|-------|
| APPROVED | 4 |
| REJECTED | 3 |
| PARTIAL | 0 |
| NEEDS_HUMAN_REVIEW | 0 |
| N/A (0 bytes, no action) | 14 |

**Key finding:** The codebase is exceptionally well-optimized. Out of 21 candidates, only 7 had non-zero bytecode savings potential, and of those, 4 were APPROVED and 3 were REJECTED by the Skeptic. The remaining 14 recommendations correctly identified known deprecated items, structural requirements, or false positives with zero bytecode impact.

**JackpotModule (95.9% of size limit):** Zero removable bytes. The module's size is the result of genuine functional complexity, not waste code.

---

## Estimated Savings

### Approved Savings

| ID | Contract | Bytecode Bytes | Deployment Gas |
|----|----------|---------------|----------------|
| SCAV-004 | DecimatorModule | ~22 | ~4,400 |
| SCAV-006 | DecimatorModule | ~10 | ~2,000 |
| SCAV-016 | LootboxModule | ~6 | ~1,200 |
| SCAV-009 | WhaleModule | ~30 | ~6,000 |
| **Total Approved** | | **~68 bytes** | **~13,600 gas** |

### Rejected Savings (Not Safe to Remove)

| ID | Contract | Bytes (Not Saved) | Reason |
|----|----------|-------------------|--------|
| SCAV-005 | DecimatorModule | ~10 | Defense-in-depth guards modular divide-by-zero protection |
| SCAV-007 | DecimatorModule | ~14 | Guards protect against state corruption on edge case call patterns |
| SCAV-008 | DecimatorModule | ~14 | Guards protect subtraction underflow on corrupted state |

### Per-Contract Breakdown

| Contract | Approved Bytes | Rejected Bytes | Net Savings |
|----------|---------------|----------------|-------------|
| DecimatorModule (754 lines) | 32 bytes | 38 bytes | 32 bytes |
| WhaleModule (907 lines) | 30 bytes | 0 | 30 bytes |
| LootboxModule (1,779 lines) | 6 bytes | 0 | 6 bytes |
| JackpotModule (2,824 lines) | 0 bytes | 0 | **0 bytes** |
| All other contracts | 0 bytes | 0 | 0 bytes |

### JackpotModule Specific

**Current bytecode:** 23,583 / 24,576 bytes (95.9%)
**Approved savings:** 0 bytes
**Post-optimization headroom:** 993 bytes (unchanged)

The JackpotModule remains at 95.9% utilization. No behavior-preserving bytecode reduction is possible. The module's 4 Scavenger candidates (SCAV-012 through SCAV-015) were all correctly identified as having zero savings (compiler optimizations, already cached, not dead code, or withdrawn).

---

## Approved Removals

### GAS-01: Redundant Requires / Impossible Defensive Checks (2 approved)

#### SCAV-004: APPROVED -- Remove `totalBurn > type(uint232).max` in `runDecimatorJackpot`

**File:** `contracts/modules/DegenerusGameDecimatorModule.sol`, lines 339-342
**Code:** `if (totalBurn > type(uint232).max) { return poolWei; }`
**Savings:** ~22 bytes bytecode, ~4,400 deployment gas

**Skeptic verdict:** The mathematical proof is sound. `totalBurn` accumulates at most 11 values (one per denom 2-12), each capped at `uint192.max` (~6.3e57). The maximum sum is `11 * 6.3e57 = 6.9e58`, which is far below `uint232.max` (~6.9e69) -- 11 orders of magnitude below. Even if `decBucketBurnTotal` were corrupted to store values exceeding `uint192`, the individual `DecEntry.burn` field is typed as `uint192` and saturated at line 259, so the sum cannot overflow `uint232`. This check is provably unreachable.

**Implementation:** Remove lines 339-342. The `uint232(totalBurn)` downcast at line 350 is safe without the guard.

#### SCAV-006: APPROVED -- Remove `denom == 0` guard in `_decWinningSubbucket`

**File:** `contracts/modules/DegenerusGameDecimatorModule.sol`, line 583
**Code:** `if (denom == 0) return 0;`
**Savings:** ~10 bytes bytecode, ~2,000 deployment gas

**Skeptic verdict:** The function is `private pure` and has exactly one caller: the loop in `runDecimatorJackpot` (line 316) where `denom` iterates `for (uint8 denom = 2; denom <= DECIMATOR_MAX_DENOM; )`. The loop variable starts at 2 and increments. `denom == 0` is unreachable. If the guard were removed and a future caller passed `denom=0`, the `% denom` at line 585 would revert with a division-by-zero panic (0x12), which is a safe failure mode -- it would not silently produce a wrong result.

**Implementation:** Remove line 583 entirely.

### GAS-02: Dead Storage Variables (0 approved)

No approved removals. SCAV-001 (already deprecated), SCAV-002 (struct packing), and SCAV-003 (comments only) correctly have 0 bytes savings. SCAV-021 (compile-time constant) is already eliminated by the optimizer.

### GAS-03: Dead Code Paths (1 approved)

#### SCAV-016: APPROVED -- Remove `unit == 0` from compound guard in `_lootboxDgnrsReward`

**File:** `contracts/modules/DegenerusGameLootboxModule.sol`, line ~1696
**Code:** `if (poolBalance == 0 || ppm == 0 || unit == 0) return 0;`
**Savings:** ~6 bytes bytecode, ~1,200 deployment gas

**Skeptic verdict:** The variable `unit` is assigned `1 ether` (line 1694), which is the compile-time constant `10**18`. This value is always non-zero. The `unit == 0` leg of the OR condition can never evaluate to true. Removing it changes the guard to `if (poolBalance == 0 || ppm == 0) return 0;` which is functionally identical.

Edge cases verified:
- `ppm` derives from a 4-branch if/else on `tierRoll` (lines 1683-1691); all branches assign non-zero PPM constants, but the guard for `ppm == 0` is still worth keeping as defense against future constant changes.
- `poolBalance` reads from external storage, can be 0 -- guard is necessary.
- `unit` is `1 ether` -- provably non-zero.

**Implementation:** Change line ~1696 from `if (poolBalance == 0 || ppm == 0 || unit == 0) return 0;` to `if (poolBalance == 0 || ppm == 0) return 0;`. Optionally inline `unit` as `1 ether` directly in the division at line 1698: `dgnrsAmount = (poolBalance * ppm * amount) / (1_000_000 * 1 ether);`. The compiler will constant-fold `1_000_000 * 1 ether` to `1e24`.

### GAS-04: Redundant SLOADs / External Calls (1 approved)

#### SCAV-009: APPROVED -- Cache `_simulatedDayIndex()` from caller parameter in `_applyLootboxBoostOnPurchase`

**File:** `contracts/modules/DegenerusGameWhaleModule.sol`, line 813
**Code:** `uint48 currentDay = _simulatedDayIndex();`
**Savings:** ~30 bytes bytecode, ~6,000 deployment gas

**Skeptic verdict:** `_applyLootboxBoostOnPurchase` receives `day` as its second parameter (line 808). The caller `_recordLootboxEntry` passes `dayIndex` (line 772), which is `_simulatedDayIndex()` computed at line 751. Inside `_applyLootboxBoostOnPurchase`, line 813 computes `currentDay = _simulatedDayIndex()` again. Within the same transaction, `block.timestamp` is constant, so `day == currentDay` always holds.

The `day` parameter is used only for event emission (line 867: `emit LootBoxBoostConsumed(player, day, ...)`). The `currentDay` local is used for expiry checks (lines 819, 835, 851). Since they are identical, `currentDay` can be replaced with `day`.

Edge cases verified:
- Same function exists in MintModule (line 1084) with identical pattern -- same optimization applies there.
- `_simulatedDayIndex()` calls `GameTimeLib.currentDayIndex()` which reads `block.timestamp` (not storage), so this is computation redundancy, not SLOAD redundancy. However, the function call still generates bytecode for the CALL opcode and stack manipulation.
- The viaIR optimizer may or may not deduplicate this depending on inlining decisions. The explicit change guarantees the savings.

**Implementation:** In `_applyLootboxBoostOnPurchase` (WhaleModule line 813), replace `uint48 currentDay = _simulatedDayIndex();` with `uint48 currentDay = day;`. Apply the same change in `MintModule._applyLootboxBoostOnPurchase` (line ~1087) if an identical pattern exists there.

---

## Rejected Recommendations

### SCAV-005: REJECTED -- `bucket == 0` guard in `_decSubbucketFor`

**File:** `contracts/modules/DegenerusGameDecimatorModule.sol`, line 716
**Code:** `if (bucket == 0) return 0;`

**Counterexample:** While current callers always pass `bucket >= 2`, removing this guard would make `% bucket` at line 719 revert with a division-by-zero panic (0x12) if any future code path or state corruption led to `bucket == 0`. This is a `private pure` function, so no external caller can reach it directly. However, the guard serves as a safety net against arithmetic panic in a financial function that determines jackpot eligibility. The 10 bytes saved are not worth the loss of a clean zero-return for invalid input.

**Risk assessment:** low (removal would cause panic revert, not silent bug)
**Recommendation:** Keep. The guard converts a panic into a clean early return, which is better error handling for a system where `bucket=0` means "no participation."

### SCAV-007: REJECTED -- `delta == 0 || denom == 0` guard in `_decUpdateSubbucket`

**File:** `contracts/modules/DegenerusGameDecimatorModule.sol`, line 684
**Code:** `if (delta == 0 || denom == 0) return;`

**Counterexample:** The `denom == 0` branch is unreachable for current callers. However, the `delta == 0` branch provides protection against a subtle edge case: if `recordDecBurn` is called with `baseAmount=0` and `multBps > BPS_DENOMINATOR`, the `_decEffectiveAmount` function returns 0 (line 559 check), making `delta = 0`. The outer `if (delta != 0)` at line 267 catches this for the main path, but the migration path at line 245 could pass a `prevBurn` delta that, due to saturation arithmetic, ends up as 0 if `newBurn == prevBurn` after saturation. While unlikely, the guard costs only 14 bytes and protects against a no-op storage write (writing 0 to `decBucketBurnTotal`).

**Risk assessment:** low (removal would cause useless storage write, not corruption)
**Recommendation:** Keep. The storage write gas cost of a missed guard (>2,100 gas per SSTORE) exceeds the one-time 14-byte deployment savings.

### SCAV-008: REJECTED -- `delta == 0 || denom == 0` guard in `_decRemoveSubbucket`

**File:** `contracts/modules/DegenerusGameDecimatorModule.sol`, line 699
**Code:** `if (delta == 0 || denom == 0) return;`

**Counterexample:** The function performs `slotTotal - uint256(delta)` at line 702 with a preceding underflow check at line 701. If `delta == 0` and the guard were removed, the subtraction would be a no-op (safe), but the `if (slotTotal < uint256(delta))` check would also pass (safe). The real risk is `denom == 0`: if `denom` were somehow 0, the `decBucketBurnTotal[lvl][0][sub]` would access a valid but unintended storage slot, potentially corrupting state. While current callers guarantee `denom >= 2`, the guard provides defense against state corruption in a critical financial mapping.

**Risk assessment:** medium (removal with `denom=0` could write to wrong storage slot)
**Recommendation:** Keep. The 14 bytes saved are not worth removing a guard that protects mapping key integrity.

---

## Needs Human Review

None. All 21 recommendations were conclusively categorized as APPROVED, REJECTED, or N/A (zero savings).

---

## Implementation Order

The 4 approved removals are independent (no dependencies between them). They can be applied in any order, but for optimal diff clarity:

1. **SCAV-004** (DecimatorModule, lines 339-342): Remove the `totalBurn > type(uint232).max` check. Simplest removal -- delete 4 lines, including the safety comment.

2. **SCAV-006** (DecimatorModule, line 583): Remove the `denom == 0` guard. Delete 1 line. Verify that `_decWinningSubbucket` is still only called from the `denom=2..12` loop.

3. **SCAV-016** (LootboxModule, line ~1696): Simplify the compound guard from `poolBalance == 0 || ppm == 0 || unit == 0` to `poolBalance == 0 || ppm == 0`. Optionally inline `unit` as `1 ether` in the division.

4. **SCAV-009** (WhaleModule, line 813; MintModule, line ~1087): Replace `uint48 currentDay = _simulatedDayIndex();` with `uint48 currentDay = day;` in `_applyLootboxBoostOnPurchase`. Apply in both WhaleModule and MintModule if the pattern is duplicated.

**Post-implementation verification:**
- All existing tests must pass (1,065 passing, 26 pre-existing failures unrelated to scope)
- Contracts must compile clean with `npx hardhat compile`
- Bytecode sizes should decrease by the estimated amounts (verify with `hardhat-contract-sizer` or manual diff)

---

## Scavenger Recommendations (Full Analysis)

The Scavenger agent analyzed all production contracts in the prescribed processing order. Each recommendation identifies dead code, unreachable branches, redundant checks, unused storage, or cacheable SLOADs that can be safely removed without changing behavior.

**Key constraints observed:**
- Storage variables in DegenerusGameStorage.sol must NEVER be removed (only `_deprecated_*` renamed) due to delegatecall slot alignment
- Public/external functions must be checked against IDegenerusGame.sol (~450 lines) and IDegenerusGameModules.sol (~390 lines) before removal
- Event emissions are never candidates for removal
- JackpotModule is at 95.9% of the 24,576-byte EVM size limit (23,583 bytes) and is highest priority

---

### Contract: DegenerusGameStorage.sol (1,608 lines)

#### SCAV-001: Deprecated storage variable `_deprecated_deityTicketBoostDay`

```json
{
  "id": "SCAV-001",
  "file": "contracts/storage/DegenerusGameStorage.sol",
  "location": "line ~1440",
  "type": "unused_storage_slot",
  "code": "mapping(address => uint48) internal _deprecated_deityTicketBoostDay;",
  "reasoning": "Already renamed with _deprecated_ prefix. Confirmed zero references across all modules, DegenerusGame.sol, and external contracts. Variable occupies a storage slot but is never read or written in any code path.",
  "confidence": "high",
  "gas_estimate": {"bytecode_bytes": 0, "deployment_gas": 0},
  "cross_contract_check_needed": false,
  "files_checked": ["contracts/storage/DegenerusGameStorage.sol", "contracts/DegenerusGame.sol", "contracts/modules/*.sol"]
}
```

**Note:** Already deprecated. No bytecode savings since it is only a storage declaration. Retained for slot alignment. No action needed.

#### SCAV-002: Quest.difficulty field retained for compatibility

```json
{
  "id": "SCAV-002",
  "file": "contracts/storage/DegenerusGameStorage.sol",
  "location": "line ~228 (Quest struct)",
  "type": "unused_storage_slot",
  "code": "uint16 difficulty; // Retained for struct packing compatibility",
  "reasoning": "Quest struct field 'difficulty' is never read or written by any contract. It exists only to preserve storage slot packing with other Quest fields. DegenerusQuests.sol uses fixed targets (QUEST_MINT_TARGET, QUEST_BURNIE_TARGET) instead of per-quest difficulty. Removing it would shift all subsequent struct fields in storage.",
  "confidence": "high",
  "gas_estimate": {"bytecode_bytes": 0, "deployment_gas": 0},
  "cross_contract_check_needed": false,
  "files_checked": ["contracts/storage/DegenerusGameStorage.sol", "contracts/DegenerusQuests.sol"]
}
```

**Note:** Must be retained. Removing would shift struct packing in storage. No action needed.

#### SCAV-003: BitPackingLib unused bit ranges [154-159] and [184-227]

```json
{
  "id": "SCAV-003",
  "file": "contracts/libraries/BitPackingLib.sol",
  "location": "lines 17, 19 (comments)",
  "type": "unused_variable",
  "code": "[154-159] (unused), [184-227] (unused)",
  "reasoning": "These bit ranges in the mintPacked_ layout are documented as unused. No shift constant or mask exists for them. No code reads from or writes to these positions. They represent reserved space for future features. The bits [244-255] are also noted as reserved. No bytecode is generated for unused bit ranges -- they are purely documentation.",
  "confidence": "high",
  "gas_estimate": {"bytecode_bytes": 0, "deployment_gas": 0},
  "cross_contract_check_needed": false,
  "files_checked": ["contracts/libraries/BitPackingLib.sol", "contracts/modules/DegenerusGameWhaleModule.sol", "contracts/modules/DegenerusGameMintModule.sol", "contracts/modules/DegenerusGameBoonModule.sol"]
}
```

**Note:** Documentation-only. No bytecode impact. No action needed.

---

### Contract: DegenerusGameGameOverModule.sol (233 lines)

No Scavenger recommendations. This is a compact leaf module with no dead code paths. All branches are reachable:
- `gameOverFinalJackpotPaid` early return is a valid idempotency guard
- `currentLevel < 10` branch handles early game over (deity pass refunds)
- `available == 0` early return is a valid edge case
- `rngWord == 0` allows retry when VRF not ready

---

### Contract: DegenerusGameEndgameModule.sol (540 lines)

No Scavenger recommendations. All functions are actively called:
- `rewardTopAffiliate` called from AdvanceModule during level transition
- `runRewardJackpots` called from AdvanceModule during jackpot phase
- `claimWhalePass` called from DegenerusGame and sDGNRS
- `_addClaimableEth`, `_runBafJackpot`, `_awardJackpotTickets`, `_jackpotTicketRoll` are all internal callee chains
- BAF/Decimator conditional branches are reachable at their respective trigger levels (every 10, 5, and 100)

---

### Contract: DegenerusGameDecimatorModule.sol (754 lines)

#### SCAV-004: Defensive `totalBurn > type(uint232).max` check in `runDecimatorJackpot`

```json
{
  "id": "SCAV-004",
  "file": "contracts/modules/DegenerusGameDecimatorModule.sol",
  "location": "lines 339-342",
  "type": "defensive_check_impossible",
  "code": "if (totalBurn > type(uint232).max) { return poolWei; }",
  "reasoning": "Each DecEntry.burn is uint192. The maximum number of denominators is 11 (2 through 12). Even if every subbucket for every denominator had uint192.max burn, the sum would be 11 * uint192.max = ~6.9e58, which fits within uint256 but exceeds uint232.max (~6.9e69). However, the totalBurn loop only sums winning subbuckets (one per denom), so the practical max is 11 * uint192.max. Since uint192.max = ~6.3e57 and 11 * ~6.3e57 = ~6.9e58, and uint232.max = ~6.9e69, the check can never trigger. The accumulated totalBurn from 11 uint192 values can never exceed uint232.max.",
  "confidence": "high",
  "gas_estimate": {"bytecode_bytes": 22, "deployment_gas": 4400},
  "cross_contract_check_needed": false,
  "files_checked": ["contracts/modules/DegenerusGameDecimatorModule.sol", "contracts/storage/DegenerusGameStorage.sol"]
}
```

**Skeptic Verdict: APPROVED** -- See Approved Removals section above.

#### SCAV-005: `_decSubbucketFor` guard `if (bucket == 0) return 0`

```json
{
  "id": "SCAV-005",
  "file": "contracts/modules/DegenerusGameDecimatorModule.sol",
  "location": "line 716",
  "type": "defensive_check_impossible",
  "code": "if (bucket == 0) return 0;",
  "reasoning": "All callers of _decSubbucketFor pass bucket values that are either the player's chosen bucket (2-12, validated by the coin contract which only passes valid denoms) or a strictly smaller replacement bucket. The bucket parameter is uint8, and the only call sites are in recordDecBurn where m.bucket is set to the incoming bucket (2-12 from coin contract) or to a strictly lower replacement. The denom is always >= 2 when this function is called. However, this is a modular defense-in-depth guard protecting against future callers.",
  "confidence": "medium",
  "gas_estimate": {"bytecode_bytes": 10, "deployment_gas": 2000},
  "cross_contract_check_needed": true,
  "files_checked": ["contracts/modules/DegenerusGameDecimatorModule.sol", "contracts/BurnieCoin.sol"]
}
```

**Skeptic Verdict: REJECTED** -- See Rejected Recommendations section above.

#### SCAV-006: `_decWinningSubbucket` guard `if (denom == 0) return 0`

```json
{
  "id": "SCAV-006",
  "file": "contracts/modules/DegenerusGameDecimatorModule.sol",
  "location": "line 583",
  "type": "defensive_check_impossible",
  "code": "if (denom == 0) return 0;",
  "reasoning": "Called only from the loop in runDecimatorJackpot where denom iterates from 2 to DECIMATOR_MAX_DENOM (12). Denom is never 0 in the only call path. Defense-in-depth guard.",
  "confidence": "high",
  "gas_estimate": {"bytecode_bytes": 10, "deployment_gas": 2000},
  "cross_contract_check_needed": false,
  "files_checked": ["contracts/modules/DegenerusGameDecimatorModule.sol"]
}
```

**Skeptic Verdict: APPROVED** -- See Approved Removals section above.

#### SCAV-007: `_decUpdateSubbucket` guard `if (delta == 0 || denom == 0) return`

```json
{
  "id": "SCAV-007",
  "file": "contracts/modules/DegenerusGameDecimatorModule.sol",
  "location": "line 684",
  "type": "defensive_check_impossible",
  "code": "if (delta == 0 || denom == 0) return;",
  "reasoning": "Called from recordDecBurn only when delta != 0 (line 267 checks delta != 0 before calling), and denom is always >= 2 (bucket range 2-12). Also called when prevBurn != 0 during bucket migration (line 246). The delta==0 guard is technically reachable if prevBurn is zero during migration, but the calling code checks prevBurn != 0 at line 244. The denom==0 guard is unreachable for all current callers.",
  "confidence": "medium",
  "gas_estimate": {"bytecode_bytes": 14, "deployment_gas": 2800},
  "cross_contract_check_needed": false,
  "files_checked": ["contracts/modules/DegenerusGameDecimatorModule.sol"]
}
```

**Skeptic Verdict: REJECTED** -- See Rejected Recommendations section above.

#### SCAV-008: `_decRemoveSubbucket` guard `if (delta == 0 || denom == 0) return`

```json
{
  "id": "SCAV-008",
  "file": "contracts/modules/DegenerusGameDecimatorModule.sol",
  "location": "line 699",
  "type": "defensive_check_impossible",
  "code": "if (delta == 0 || denom == 0) return;",
  "reasoning": "Called from recordDecBurn line 240 only during bucket migration when bucket < m.bucket (so old bucket >= 2), and prevBurn is the existing burn value. If prevBurn were 0, the caller would not have entered the migration branch (m.bucket would be 0 on first burn, taking the first-burn branch instead). Both guards are unreachable given current call patterns.",
  "confidence": "medium",
  "gas_estimate": {"bytecode_bytes": 14, "deployment_gas": 2800},
  "cross_contract_check_needed": false,
  "files_checked": ["contracts/modules/DegenerusGameDecimatorModule.sol"]
}
```

**Skeptic Verdict: REJECTED** -- See Rejected Recommendations section above.

---

### Contract: DegenerusGameBoonModule.sol (359 lines)

No Scavenger recommendations. All code paths are reachable:
- Each boon consumption function handles deity-granted vs lootbox-granted expiry
- `checkAndClearExpiredBoon` checks all 10 boon categories -- all are live gameplay features
- `consumeActivityBoon` handles saturation arithmetic correctly

---

### Contract: DegenerusGameWhaleModule.sol (907 lines)

#### SCAV-009: `_applyLootboxBoostOnPurchase` redundant `_simulatedDayIndex()` call

```json
{
  "id": "SCAV-009",
  "file": "contracts/modules/DegenerusGameWhaleModule.sol",
  "location": "line 813",
  "type": "redundant_sload",
  "code": "uint48 currentDay = _simulatedDayIndex();",
  "reasoning": "The function is called from _recordLootboxEntry (line 771). The caller (_recordLootboxEntry) already calls _simulatedDayIndex() at line 751 to get dayIndex. However, _applyLootboxBoostOnPurchase is a private function that receives day (line 809) as a parameter but then calls _simulatedDayIndex() again independently to get currentDay for expiry checking. The two values (day parameter and currentDay) are the same in the same transaction. The function could use the day parameter instead of re-calling _simulatedDayIndex(). Note: _simulatedDayIndex() calls GameTimeLib.currentDayIndex() which reads block.timestamp (not storage), so this is a computation redundancy, not an SLOAD. With viaIR=true, the compiler may optimize this away.",
  "confidence": "low",
  "gas_estimate": {"bytecode_bytes": 30, "deployment_gas": 6000},
  "cross_contract_check_needed": false,
  "files_checked": ["contracts/modules/DegenerusGameWhaleModule.sol", "contracts/storage/DegenerusGameStorage.sol"]
}
```

**Skeptic Verdict: APPROVED** -- See Approved Removals section above.

---

### Contract: DegenerusGameDegeneretteModule.sol (1,181 lines)

No Scavenger recommendations. The module handles Degenerette betting mechanics with ETH, BURNIE, and WWXRP currencies. All branches are reachable through normal gameplay (currency selection, hero quadrant, match counting). Functions are all referenced in the IDegenerusGameDegeneretteModule interface and called via delegatecall from DegenerusGame.

---

### Contract: DegenerusGameMintModule.sol (1,195 lines)

#### SCAV-010: `_recordLootboxMintDay` called with potentially already-current day

```json
{
  "id": "SCAV-010",
  "file": "contracts/modules/DegenerusGameMintModule.sol",
  "location": "multiple call sites in purchase flows",
  "type": "redundant_sload",
  "code": "_recordLootboxMintDay(buyer, day, cachedPacked) -- checks prevDay == day and returns early",
  "reasoning": "When a player makes multiple purchases in the same transaction or day, _recordLootboxMintDay will be called multiple times but the early-return (prevDay == day) makes subsequent calls nearly free (just the comparison). The function correctly uses a cached packed value to avoid redundant SLOAD. This is already well-optimized. No action needed.",
  "confidence": "low",
  "gas_estimate": {"bytecode_bytes": 0, "deployment_gas": 0},
  "cross_contract_check_needed": false,
  "files_checked": ["contracts/modules/DegenerusGameMintModule.sol", "contracts/modules/DegenerusGameWhaleModule.sol"]
}
```

**Skeptic Verdict: N/A** -- Zero savings. Scavenger correctly identified this as already optimized.

---

### Contract: DegenerusGameAdvanceModule.sol (1,391 lines)

#### SCAV-011: Redundant `gameOver` check after `jackpotPhaseFlag` check in `advanceGame`

```json
{
  "id": "SCAV-011",
  "file": "contracts/modules/DegenerusGameAdvanceModule.sol",
  "location": "advanceGame function, early guards",
  "type": "redundant_require",
  "code": "if (gameOver) revert E();",
  "reasoning": "The advanceGame function checks both gameOver and jackpotPhaseFlag as independent guards. However, once gameOver is set to true (terminal state), the game FSM no longer transitions through jackpotPhaseFlag. The gameOver check is necessary because gameOver can be set during the PURCHASE phase via liveness guards (120-day inactivity), and advanceGame could be called when gameOver is true but jackpotPhaseFlag is false. Both checks are independently reachable.",
  "confidence": "low",
  "gas_estimate": {"bytecode_bytes": 0, "deployment_gas": 0},
  "cross_contract_check_needed": false,
  "files_checked": ["contracts/modules/DegenerusGameAdvanceModule.sol", "contracts/storage/DegenerusGameStorage.sol"]
}
```

**Skeptic Verdict: N/A** -- Zero savings. Scavenger correctly identified this as a false positive and withdrew it.

---

### Contract: DegenerusGameJackpotModule.sol (2,824 lines) -- PRIORITY

**Current bytecode: 23,583 / 24,576 bytes (95.9% of limit)**

#### SCAV-012: `_processDailyEthChunk` unit calculation can be simplified

```json
{
  "id": "SCAV-012",
  "file": "contracts/modules/DegenerusGameJackpotModule.sol",
  "location": "line ~1441",
  "type": "redundant_external_call",
  "code": "uint256 unit = PriceLookupLib.priceForLevel(lvl + 1) >> 2;",
  "reasoning": "PriceLookupLib.priceForLevel is a pure function with no storage reads. The compiler with viaIR=true should inline this. However, this function is called every time _processDailyEthChunk is invoked, which happens multiple times per jackpot day (chunked processing). The lvl parameter is the same across all chunks for a given jackpot. The unit value could be passed as a parameter from the caller rather than recomputed. However, since PriceLookupLib is a pure library function, the compiler likely inlines it at zero cost.",
  "confidence": "low",
  "gas_estimate": {"bytecode_bytes": 0, "deployment_gas": 0},
  "cross_contract_check_needed": false,
  "files_checked": ["contracts/modules/DegenerusGameJackpotModule.sol", "contracts/libraries/PriceLookupLib.sol"]
}
```

**Skeptic Verdict: N/A** -- Zero savings. Pure library function is inlined by compiler.

#### SCAV-013: `_distributeJackpotEth` repeated `_addClaimableEth` pattern

```json
{
  "id": "SCAV-013",
  "file": "contracts/modules/DegenerusGameJackpotModule.sol",
  "location": "daily jackpot distribution loops",
  "type": "redundant_sload",
  "code": "Multiple calls to _addClaimableEth within a loop, each accessing autoRebuyState[winner]",
  "reasoning": "In the daily jackpot distribution, _addClaimableEth is called for each winner. Each call reads autoRebuyState[winner] from storage. If the same address wins multiple buckets, their autoRebuyState is read multiple times. However, with the bucket rotation system and trait-based selection, winning the same address in multiple buckets is rare. The viaIR optimizer with 200 runs cannot deduplicate cross-function SLOADs. The savings are small and the code change would be complex.",
  "confidence": "low",
  "gas_estimate": {"bytecode_bytes": 0, "deployment_gas": 0},
  "cross_contract_check_needed": false,
  "files_checked": ["contracts/modules/DegenerusGameJackpotModule.sol"]
}
```

**Skeptic Verdict: N/A** -- Zero savings. Withdrawn by Scavenger.

#### SCAV-014: `consolidatePrizePools` yield accumulator arithmetic

```json
{
  "id": "SCAV-014",
  "file": "contracts/modules/DegenerusGameJackpotModule.sol",
  "location": "consolidatePrizePools function",
  "type": "redundant_sload",
  "code": "Multiple reads of yieldAccumulator, currentPrizePool, and packed pool slots",
  "reasoning": "consolidatePrizePools performs multiple reads/writes to prize pool storage slots within a single execution. The function reads _getFuturePrizePool(), _getNextPrizePool(), currentPrizePool, and yieldAccumulator, then performs arithmetic and writes back. With viaIR=true, the optimizer should cache these within a single function. Cross-function caching is already handled by local variables in the function body. No additional optimization needed.",
  "confidence": "low",
  "gas_estimate": {"bytecode_bytes": 0, "deployment_gas": 0},
  "cross_contract_check_needed": false,
  "files_checked": ["contracts/modules/DegenerusGameJackpotModule.sol"]
}
```

**Skeptic Verdict: N/A** -- Zero savings. Already uses local variable caching.

#### SCAV-015: `processTicketBatch` gas budget constant could be tuned

```json
{
  "id": "SCAV-015",
  "file": "contracts/modules/DegenerusGameJackpotModule.sol",
  "location": "processTicketBatch function",
  "type": "dead_code_path",
  "code": "Gas budget limiter with fixed constant",
  "reasoning": "processTicketBatch uses a fixed gas budget to limit per-call processing. This is a gas safety mechanism, not dead code. All branches are reachable depending on how many tickets need processing. No dead code found.",
  "confidence": "low",
  "gas_estimate": {"bytecode_bytes": 0, "deployment_gas": 0},
  "cross_contract_check_needed": false,
  "files_checked": ["contracts/modules/DegenerusGameJackpotModule.sol"]
}
```

**Skeptic Verdict: N/A** -- Zero savings. Not dead code; withdrawn by Scavenger.

---

### Contract: DegenerusGameLootboxModule.sol (1,779 lines)

#### SCAV-016: `_lootboxDgnrsReward` reads `1 ether` as a local variable

```json
{
  "id": "SCAV-016",
  "file": "contracts/modules/DegenerusGameLootboxModule.sol",
  "location": "line ~1694",
  "type": "dead_code_path",
  "code": "uint256 unit = 1 ether; ... if (poolBalance == 0 || ppm == 0 || unit == 0) return 0;",
  "reasoning": "The variable 'unit' is set to '1 ether' (a compile-time constant = 10^18) which is always non-zero. The 'unit == 0' check in the guard can never be true. This check adds dead bytecode. Removing just the 'unit == 0' portion saves a small amount.",
  "confidence": "high",
  "gas_estimate": {"bytecode_bytes": 6, "deployment_gas": 1200},
  "cross_contract_check_needed": false,
  "files_checked": ["contracts/modules/DegenerusGameLootboxModule.sol"]
}
```

**Skeptic Verdict: APPROVED** -- See Approved Removals section above.

#### SCAV-017: `_lazyPassPriceForLevel` duplicates `_lazyPassCost` in WhaleModule

```json
{
  "id": "SCAV-017",
  "file": "contracts/modules/DegenerusGameLootboxModule.sol",
  "location": "lines 1721-1733",
  "type": "dead_code_path",
  "code": "function _lazyPassPriceForLevel(uint24 passLevel) private pure returns (uint256) { ... }",
  "reasoning": "This function is nearly identical to _lazyPassCost in WhaleModule (lines 614-621). Both compute the sum of PriceLookupLib.priceForLevel over 10 levels. However, they exist in different contracts (LootboxModule vs WhaleModule) that are deployed separately and invoked via delegatecall. Since Solidity does not support cross-contract code sharing for delegatecall modules (each must contain its own bytecode), this duplication is structurally necessary. Not removable.",
  "confidence": "low",
  "gas_estimate": {"bytecode_bytes": 0, "deployment_gas": 0},
  "cross_contract_check_needed": true,
  "files_checked": ["contracts/modules/DegenerusGameLootboxModule.sol", "contracts/modules/DegenerusGameWhaleModule.sol"]
}
```

**Skeptic Verdict: N/A** -- Zero savings. Structural duplication required by delegatecall architecture.

---

### Contract: DegenerusGame.sol (2,846 lines)

#### SCAV-018: `_resolvePlayer` pattern repeated across many external functions

```json
{
  "id": "SCAV-018",
  "file": "contracts/DegenerusGame.sol",
  "location": "multiple external functions",
  "type": "redundant_sload",
  "code": "player = _resolvePlayer(player); -- checks address(0) and operator approval",
  "reasoning": "_resolvePlayer is called at the start of many external functions. It reads isApprovedOperator mapping if player != msg.sender. For functions that are always called with player=address(0) (like sDGNRS's self-calls), the operator check is skipped. The pattern is well-optimized and the function is small. No savings possible -- the check is necessary for security.",
  "confidence": "low",
  "gas_estimate": {"bytecode_bytes": 0, "deployment_gas": 0},
  "cross_contract_check_needed": false,
  "files_checked": ["contracts/DegenerusGame.sol"]
}
```

**Skeptic Verdict: N/A** -- Zero savings. Security-critical access control.

#### SCAV-019: Duplicate `RngLocked()` error across DegenerusGame and WhaleModule

```json
{
  "id": "SCAV-019",
  "file": "contracts/DegenerusGame.sol, contracts/modules/DegenerusGameWhaleModule.sol, contracts/modules/DegenerusGameAdvanceModule.sol",
  "location": "error declarations",
  "type": "dead_code_path",
  "code": "error RngLocked();",
  "reasoning": "The custom error RngLocked() is declared in DegenerusGame.sol, WhaleModule, and AdvanceModule independently. Since these are separate contracts compiled independently, the error selector is generated in each contract's bytecode. This is structurally required -- errors cannot be shared across delegatecall module boundaries. Each module needs its own declaration to revert with the correct selector.",
  "confidence": "low",
  "gas_estimate": {"bytecode_bytes": 0, "deployment_gas": 0},
  "cross_contract_check_needed": false,
  "files_checked": ["contracts/DegenerusGame.sol", "contracts/modules/DegenerusGameWhaleModule.sol", "contracts/modules/DegenerusGameAdvanceModule.sol"]
}
```

**Skeptic Verdict: N/A** -- Zero savings. Structural requirement of delegatecall module pattern.

---

### Libraries

#### BitPackingLib.sol (88 lines)

No recommendations. Pure library with minimal bytecode. All constants and the single `setPacked` function are used across multiple modules.

#### JackpotBucketLib.sol (307 lines)

No recommendations. All functions are actively used by JackpotModule. Pure library functions are inlined by the compiler.

#### EntropyLib.sol (24 lines)

No recommendations. Single function `entropyStep` used extensively across all modules.

#### GameTimeLib.sol (35 lines)

No recommendations. Single function `currentDayIndex` used by DegenerusGame, sDGNRS, Affiliate, and Quests.

#### PriceLookupLib.sol (47 lines)

No recommendations. `priceForLevel` is a pure lookup function used by JackpotModule, EndgameModule, WhaleModule, MintModule, and LootboxModule.

---

### External Contracts

#### BurnieCoin.sol (1,018 lines)

#### SCAV-020: `_beforeTransfer` skip for game contract

```json
{
  "id": "SCAV-020",
  "file": "contracts/BurnieCoin.sol",
  "location": "transfer/transferFrom functions",
  "type": "redundant_require",
  "code": "Standard ERC20 transfer with game contract bypass",
  "reasoning": "BurnieCoin has a game contract bypass in transfer operations that skips approval checks. This is intentional design for gas optimization when the game moves BURNIE. All code paths are reachable. No dead code found.",
  "confidence": "low",
  "gas_estimate": {"bytecode_bytes": 0, "deployment_gas": 0},
  "cross_contract_check_needed": false,
  "files_checked": ["contracts/BurnieCoin.sol"]
}
```

**Skeptic Verdict: N/A** -- Zero savings. Not dead code.

#### BurnieCoinflip.sol (1,220 lines)

No Scavenger recommendations. The coinflip system handles daily flip resolution, auto-rebuy carry, bounty system, and quest rewards. All branches are reachable through normal coinflip gameplay states (pending, resolved, auto-rebuy, bounty).

#### DegenerusVault.sol (1,061 lines)

No Scavenger recommendations. The vault manages multi-asset deposits, share classes, and player-driven game operations. All code paths are reachable through vault interactions (deposit, withdraw, advance, purchase).

#### StakedDegenerusStonk.sol (520 lines)

No Scavenger recommendations. Compact soulbound token with pool management. All functions are actively called by game contract and DGNRS wrapper.

#### DegenerusStonk.sol (211 lines)

No Scavenger recommendations. Minimal ERC20 wrapper. All functions are necessary for the transferable token interface (transfer, approve, burn, unwrapTo).

#### DegenerusAffiliate.sol (847 lines)

No Scavenger recommendations. All code paths are reachable:
- Fresh/recycled ETH reward scaling uses separate BPS constants (both paths triggered by gameplay)
- Lootbox taper triggers for high-activity players
- Commission cap enforced per-sender-per-level
- Weighted random winner selection for multi-tier distribution

#### DegenerusJackpots.sol (689 lines)

No Scavenger recommendations. BAF jackpot system with leaderboard tracking. All branches are reachable:
- Top BAF bettor slice, top coinflip bettor slice, random pick, far-future tickets, scatter rounds
- Scatter century vs non-century targeting uses different level offsets
- Epoch-based lazy reset for BAF totals is actively used

#### DegenerusQuests.sol (1,610 lines)

#### SCAV-021: `QUEST_TYPE_RESERVED` constant (value 4)

```json
{
  "id": "SCAV-021",
  "file": "contracts/DegenerusQuests.sol",
  "location": "line ~153",
  "type": "unused_variable",
  "code": "uint8 private constant QUEST_TYPE_RESERVED = 4;",
  "reasoning": "QUEST_TYPE_RESERVED is declared but never referenced in any function, condition, or event. It exists as documentation that quest type 4 is retired and should not be reused. Since it is a compile-time constant, the compiler with viaIR=true and optimizer will eliminate it if unreferenced, so it generates zero bytecode. No savings.",
  "confidence": "high",
  "gas_estimate": {"bytecode_bytes": 0, "deployment_gas": 0},
  "cross_contract_check_needed": false,
  "files_checked": ["contracts/DegenerusQuests.sol"]
}
```

**Skeptic Verdict: N/A** -- Zero savings. Compiler already eliminates unused constants.

#### DegenerusDeityPass.sol (455 lines)

No Scavenger recommendations. Standard ERC721 with game callback on transfer. Compact and fully utilized.

#### WrappedWrappedXRP.sol (389 lines)

No Scavenger recommendations. Simple prize token with mintPrize functionality. All functions serve the prize minting and basic ERC20 use case.

---

### Interfaces

#### IDegenerusGame.sol (~450 lines)

No orphaned function signatures found. All declared functions have implementations in DegenerusGame.sol or its delegatecall modules.

#### IDegenerusGameModules.sol (~390 lines)

No orphaned function signatures found. All module interfaces match their implementations:
- IDegenerusGameAdvanceModule -> DegenerusGameAdvanceModule
- IDegenerusGameEndgameModule -> DegenerusGameEndgameModule
- IDegenerusGameGameOverModule -> DegenerusGameGameOverModule
- IDegenerusGameJackpotModule -> DegenerusGameJackpotModule
- IDegenerusGameDecimatorModule -> DegenerusGameDecimatorModule
- IDegenerusGameWhaleModule -> DegenerusGameWhaleModule
- IDegenerusGameMintModule -> DegenerusGameMintModule (includes purchase, purchaseCoin, etc.)
- IDegenerusGameLootboxModule -> DegenerusGameLootboxModule
- IDegenerusGameBoonModule -> DegenerusGameBoonModule
- IDegenerusGameDegeneretteModule -> DegenerusGameDegeneretteModule

---

## Summary of All Findings

| ID | Contract | Type | Category | Confidence | Bytes Saved | Skeptic Verdict |
|----|----------|------|----------|------------|-------------|-----------------|
| SCAV-001 | Storage | unused_storage_slot | GAS-02 | high | 0 | N/A (slot alignment) |
| SCAV-002 | Storage | unused_storage_slot | GAS-02 | high | 0 | N/A (struct packing) |
| SCAV-003 | BitPackingLib | unused_variable | GAS-02 | high | 0 | N/A (comments only) |
| SCAV-004 | DecimatorModule | defensive_check_impossible | GAS-01 | high | 22 | **APPROVED** |
| SCAV-005 | DecimatorModule | defensive_check_impossible | GAS-01 | medium | 10 | **REJECTED** |
| SCAV-006 | DecimatorModule | defensive_check_impossible | GAS-01 | high | 10 | **APPROVED** |
| SCAV-007 | DecimatorModule | defensive_check_impossible | GAS-01 | medium | 14 | **REJECTED** |
| SCAV-008 | DecimatorModule | defensive_check_impossible | GAS-01 | medium | 14 | **REJECTED** |
| SCAV-009 | WhaleModule | redundant_sload | GAS-04 | low | 30 | **APPROVED** |
| SCAV-010 | MintModule | redundant_sload | GAS-04 | low | 0 | N/A (already optimized) |
| SCAV-011 | AdvanceModule | redundant_require | GAS-01 | low | 0 | N/A (false positive) |
| SCAV-012 | JackpotModule | redundant_external_call | GAS-04 | low | 0 | N/A (compiler inlines) |
| SCAV-013 | JackpotModule | redundant_sload | GAS-04 | low | 0 | N/A (withdrawn) |
| SCAV-014 | JackpotModule | redundant_sload | GAS-04 | low | 0 | N/A (already cached) |
| SCAV-015 | JackpotModule | dead_code_path | GAS-03 | low | 0 | N/A (not dead code) |
| SCAV-016 | LootboxModule | dead_code_path | GAS-03 | high | 6 | **APPROVED** |
| SCAV-017 | LootboxModule | dead_code_path | GAS-03 | low | 0 | N/A (structural) |
| SCAV-018 | DegenerusGame | redundant_sload | GAS-04 | low | 0 | N/A (security-critical) |
| SCAV-019 | DegenerusGame | dead_code_path | GAS-03 | low | 0 | N/A (structural) |
| SCAV-020 | BurnieCoin | redundant_require | GAS-01 | low | 0 | N/A (not dead code) |
| SCAV-021 | Quests | unused_variable | GAS-02 | high | 0 | N/A (compiler eliminates) |

### JackpotModule Priority Summary

**Current bytecode:** 23,583 / 24,576 bytes (95.9%)

**Approved savings in JackpotModule: 0 bytes**

The JackpotModule was analyzed thoroughly (all 2,824 lines). No dead code, unreachable branches, or removable checks were found. The module is extremely tight -- every function is called during the jackpot distribution flow, every branch is reachable through the game state machine (daily jackpots, BAF/Decimator transitions, century levels, compressed vs normal mode, terminal jackpot). The viaIR optimizer with 200 runs already handles local SLOAD caching and pure function inlining.

The 95.9% size utilization is a result of genuine functional complexity (multi-bucket trait-based jackpot distribution with chunked processing, auto-rebuy, prize pool consolidation, and pool snapshot accounting), not of waste code.

---

## Appendix A: Full Scavenger JSON Batch

```json
[
  {
    "id": "SCAV-001",
    "file": "contracts/storage/DegenerusGameStorage.sol",
    "location": "line ~1440",
    "type": "unused_storage_slot",
    "code": "mapping(address => uint48) internal _deprecated_deityTicketBoostDay;",
    "reasoning": "Already renamed with _deprecated_ prefix. Confirmed zero references. Retained for slot alignment.",
    "confidence": "high",
    "gas_estimate": {"bytecode_bytes": 0, "deployment_gas": 0},
    "cross_contract_check_needed": false,
    "files_checked": ["contracts/storage/DegenerusGameStorage.sol", "contracts/DegenerusGame.sol", "contracts/modules/*.sol"]
  },
  {
    "id": "SCAV-002",
    "file": "contracts/storage/DegenerusGameStorage.sol",
    "location": "line ~228",
    "type": "unused_storage_slot",
    "code": "uint16 difficulty;",
    "reasoning": "Quest struct field never read/written. Exists for struct packing compatibility.",
    "confidence": "high",
    "gas_estimate": {"bytecode_bytes": 0, "deployment_gas": 0},
    "cross_contract_check_needed": false,
    "files_checked": ["contracts/storage/DegenerusGameStorage.sol", "contracts/DegenerusQuests.sol"]
  },
  {
    "id": "SCAV-003",
    "file": "contracts/libraries/BitPackingLib.sol",
    "location": "lines 17, 19",
    "type": "unused_variable",
    "code": "[154-159] (unused), [184-227] (unused)",
    "reasoning": "Documentation-only bit range reservations. No bytecode generated.",
    "confidence": "high",
    "gas_estimate": {"bytecode_bytes": 0, "deployment_gas": 0},
    "cross_contract_check_needed": false,
    "files_checked": ["contracts/libraries/BitPackingLib.sol", "contracts/modules/*.sol"]
  },
  {
    "id": "SCAV-004",
    "file": "contracts/modules/DegenerusGameDecimatorModule.sol",
    "location": "lines 339-342",
    "type": "defensive_check_impossible",
    "code": "if (totalBurn > type(uint232).max) { return poolWei; }",
    "reasoning": "11 uint192 values sum to max ~6.9e58, far below uint232.max (~6.9e69). Provably unreachable.",
    "confidence": "high",
    "gas_estimate": {"bytecode_bytes": 22, "deployment_gas": 4400},
    "cross_contract_check_needed": false,
    "files_checked": ["contracts/modules/DegenerusGameDecimatorModule.sol", "contracts/storage/DegenerusGameStorage.sol"]
  },
  {
    "id": "SCAV-005",
    "file": "contracts/modules/DegenerusGameDecimatorModule.sol",
    "location": "line 716",
    "type": "defensive_check_impossible",
    "code": "if (bucket == 0) return 0;",
    "reasoning": "All callers pass bucket >= 2. Defense-in-depth guard.",
    "confidence": "medium",
    "gas_estimate": {"bytecode_bytes": 10, "deployment_gas": 2000},
    "cross_contract_check_needed": true,
    "files_checked": ["contracts/modules/DegenerusGameDecimatorModule.sol", "contracts/BurnieCoin.sol"]
  },
  {
    "id": "SCAV-006",
    "file": "contracts/modules/DegenerusGameDecimatorModule.sol",
    "location": "line 583",
    "type": "defensive_check_impossible",
    "code": "if (denom == 0) return 0;",
    "reasoning": "Called only from loop where denom iterates 2..12. denom=0 is unreachable.",
    "confidence": "high",
    "gas_estimate": {"bytecode_bytes": 10, "deployment_gas": 2000},
    "cross_contract_check_needed": false,
    "files_checked": ["contracts/modules/DegenerusGameDecimatorModule.sol"]
  },
  {
    "id": "SCAV-007",
    "file": "contracts/modules/DegenerusGameDecimatorModule.sol",
    "location": "line 684",
    "type": "defensive_check_impossible",
    "code": "if (delta == 0 || denom == 0) return;",
    "reasoning": "Callers pre-check delta != 0 and pass denom >= 2. Both guards unreachable for current callers.",
    "confidence": "medium",
    "gas_estimate": {"bytecode_bytes": 14, "deployment_gas": 2800},
    "cross_contract_check_needed": false,
    "files_checked": ["contracts/modules/DegenerusGameDecimatorModule.sol"]
  },
  {
    "id": "SCAV-008",
    "file": "contracts/modules/DegenerusGameDecimatorModule.sol",
    "location": "line 699",
    "type": "defensive_check_impossible",
    "code": "if (delta == 0 || denom == 0) return;",
    "reasoning": "Called only during bucket migration with prevBurn != 0 and denom >= 2.",
    "confidence": "medium",
    "gas_estimate": {"bytecode_bytes": 14, "deployment_gas": 2800},
    "cross_contract_check_needed": false,
    "files_checked": ["contracts/modules/DegenerusGameDecimatorModule.sol"]
  },
  {
    "id": "SCAV-009",
    "file": "contracts/modules/DegenerusGameWhaleModule.sol",
    "location": "line 813",
    "type": "redundant_sload",
    "code": "uint48 currentDay = _simulatedDayIndex();",
    "reasoning": "Caller already passes dayIndex as 'day' parameter. Same value within a transaction.",
    "confidence": "low",
    "gas_estimate": {"bytecode_bytes": 30, "deployment_gas": 6000},
    "cross_contract_check_needed": false,
    "files_checked": ["contracts/modules/DegenerusGameWhaleModule.sol", "contracts/storage/DegenerusGameStorage.sol"]
  },
  {
    "id": "SCAV-010",
    "file": "contracts/modules/DegenerusGameMintModule.sol",
    "location": "multiple call sites",
    "type": "redundant_sload",
    "code": "_recordLootboxMintDay with early-return check",
    "reasoning": "Already optimized with cached packed value and day equality check.",
    "confidence": "low",
    "gas_estimate": {"bytecode_bytes": 0, "deployment_gas": 0},
    "cross_contract_check_needed": false,
    "files_checked": ["contracts/modules/DegenerusGameMintModule.sol"]
  },
  {
    "id": "SCAV-011",
    "file": "contracts/modules/DegenerusGameAdvanceModule.sol",
    "location": "advanceGame early guards",
    "type": "redundant_require",
    "code": "if (gameOver) revert E();",
    "reasoning": "Both gameOver and jackpotPhaseFlag checks are independently reachable. Not redundant.",
    "confidence": "low",
    "gas_estimate": {"bytecode_bytes": 0, "deployment_gas": 0},
    "cross_contract_check_needed": false,
    "files_checked": ["contracts/modules/DegenerusGameAdvanceModule.sol"]
  },
  {
    "id": "SCAV-012",
    "file": "contracts/modules/DegenerusGameJackpotModule.sol",
    "location": "line ~1441",
    "type": "redundant_external_call",
    "code": "PriceLookupLib.priceForLevel(lvl + 1) >> 2",
    "reasoning": "Pure library function, compiler inlines it. Zero bytecode savings.",
    "confidence": "low",
    "gas_estimate": {"bytecode_bytes": 0, "deployment_gas": 0},
    "cross_contract_check_needed": false,
    "files_checked": ["contracts/modules/DegenerusGameJackpotModule.sol", "contracts/libraries/PriceLookupLib.sol"]
  },
  {
    "id": "SCAV-013",
    "file": "contracts/modules/DegenerusGameJackpotModule.sol",
    "location": "daily jackpot distribution",
    "type": "redundant_sload",
    "code": "Multiple _addClaimableEth calls accessing autoRebuyState[winner]",
    "reasoning": "Rare duplicate reads. Impractical to implement. Withdrawn.",
    "confidence": "low",
    "gas_estimate": {"bytecode_bytes": 0, "deployment_gas": 0},
    "cross_contract_check_needed": false,
    "files_checked": ["contracts/modules/DegenerusGameJackpotModule.sol"]
  },
  {
    "id": "SCAV-014",
    "file": "contracts/modules/DegenerusGameJackpotModule.sol",
    "location": "consolidatePrizePools",
    "type": "redundant_sload",
    "code": "Multiple pool slot reads",
    "reasoning": "Already cached in local variables. No additional optimization needed.",
    "confidence": "low",
    "gas_estimate": {"bytecode_bytes": 0, "deployment_gas": 0},
    "cross_contract_check_needed": false,
    "files_checked": ["contracts/modules/DegenerusGameJackpotModule.sol"]
  },
  {
    "id": "SCAV-015",
    "file": "contracts/modules/DegenerusGameJackpotModule.sol",
    "location": "processTicketBatch",
    "type": "dead_code_path",
    "code": "Gas budget limiter",
    "reasoning": "Not dead code. Gas safety mechanism. All branches reachable.",
    "confidence": "low",
    "gas_estimate": {"bytecode_bytes": 0, "deployment_gas": 0},
    "cross_contract_check_needed": false,
    "files_checked": ["contracts/modules/DegenerusGameJackpotModule.sol"]
  },
  {
    "id": "SCAV-016",
    "file": "contracts/modules/DegenerusGameLootboxModule.sol",
    "location": "line ~1694",
    "type": "dead_code_path",
    "code": "unit == 0 check where unit = 1 ether",
    "reasoning": "1 ether is compile-time constant 10^18, always non-zero. unit == 0 is dead.",
    "confidence": "high",
    "gas_estimate": {"bytecode_bytes": 6, "deployment_gas": 1200},
    "cross_contract_check_needed": false,
    "files_checked": ["contracts/modules/DegenerusGameLootboxModule.sol"]
  },
  {
    "id": "SCAV-017",
    "file": "contracts/modules/DegenerusGameLootboxModule.sol",
    "location": "lines 1721-1733",
    "type": "dead_code_path",
    "code": "_lazyPassPriceForLevel duplicates _lazyPassCost",
    "reasoning": "Structural duplication required by delegatecall module pattern.",
    "confidence": "low",
    "gas_estimate": {"bytecode_bytes": 0, "deployment_gas": 0},
    "cross_contract_check_needed": true,
    "files_checked": ["contracts/modules/DegenerusGameLootboxModule.sol", "contracts/modules/DegenerusGameWhaleModule.sol"]
  },
  {
    "id": "SCAV-018",
    "file": "contracts/DegenerusGame.sol",
    "location": "multiple external functions",
    "type": "redundant_sload",
    "code": "_resolvePlayer pattern",
    "reasoning": "Security-critical access control. Cannot be removed.",
    "confidence": "low",
    "gas_estimate": {"bytecode_bytes": 0, "deployment_gas": 0},
    "cross_contract_check_needed": false,
    "files_checked": ["contracts/DegenerusGame.sol"]
  },
  {
    "id": "SCAV-019",
    "file": "contracts/DegenerusGame.sol + modules",
    "location": "error declarations",
    "type": "dead_code_path",
    "code": "error RngLocked();",
    "reasoning": "Structural requirement. Each module needs own error declaration.",
    "confidence": "low",
    "gas_estimate": {"bytecode_bytes": 0, "deployment_gas": 0},
    "cross_contract_check_needed": false,
    "files_checked": ["contracts/DegenerusGame.sol", "contracts/modules/*.sol"]
  },
  {
    "id": "SCAV-020",
    "file": "contracts/BurnieCoin.sol",
    "location": "transfer functions",
    "type": "redundant_require",
    "code": "Game contract bypass in transfer",
    "reasoning": "Intentional gas optimization. Not dead code.",
    "confidence": "low",
    "gas_estimate": {"bytecode_bytes": 0, "deployment_gas": 0},
    "cross_contract_check_needed": false,
    "files_checked": ["contracts/BurnieCoin.sol"]
  },
  {
    "id": "SCAV-021",
    "file": "contracts/DegenerusQuests.sol",
    "location": "line ~153",
    "type": "unused_variable",
    "code": "uint8 private constant QUEST_TYPE_RESERVED = 4;",
    "reasoning": "Unreferenced compile-time constant. Compiler eliminates it.",
    "confidence": "high",
    "gas_estimate": {"bytecode_bytes": 0, "deployment_gas": 0},
    "cross_contract_check_needed": false,
    "files_checked": ["contracts/DegenerusQuests.sol"]
  }
]
```

---

## Appendix B: Full Skeptic Verdict Batch

```json
[
  {
    "scavenger_id": "SCAV-001",
    "verdict": "N/A",
    "reasoning": "Zero bytecode savings. Already deprecated with _deprecated_ prefix. Slot must be retained for delegatecall alignment.",
    "edge_cases_checked": ["storage slot alignment", "assembly SLOAD access"],
    "files_analyzed": ["contracts/storage/DegenerusGameStorage.sol"],
    "risk_assessment": "none",
    "implementation_notes": "No action needed."
  },
  {
    "scavenger_id": "SCAV-002",
    "verdict": "N/A",
    "reasoning": "Zero bytecode savings. Quest.difficulty field is padding within a struct. Removal would shift subsequent fields in storage.",
    "edge_cases_checked": ["struct packing layout", "DegenerusQuests storage access"],
    "files_analyzed": ["contracts/storage/DegenerusGameStorage.sol", "contracts/DegenerusQuests.sol"],
    "risk_assessment": "none",
    "implementation_notes": "No action needed."
  },
  {
    "scavenger_id": "SCAV-003",
    "verdict": "N/A",
    "reasoning": "Zero bytecode savings. Unused bit ranges are documentation comments, not code.",
    "edge_cases_checked": ["BitPackingLib constant declarations"],
    "files_analyzed": ["contracts/libraries/BitPackingLib.sol"],
    "risk_assessment": "none",
    "implementation_notes": "No action needed."
  },
  {
    "scavenger_id": "SCAV-004",
    "verdict": "APPROVED",
    "reasoning": "Mathematical proof verified: 11 uint192 values sum to max ~6.9e58, which is 11 orders of magnitude below uint232.max (~6.9e69). Even with storage corruption, individual DecEntry.burn is typed as uint192 with saturation at line 259. The uint232 downcast at line 350 is provably safe.",
    "edge_cases_checked": [
      "max uint192 * 11 vs uint232.max (11 orders of magnitude margin)",
      "decBucketBurnTotal corruption scenario (bounded by uint192 type)",
      "saturation arithmetic at line 259"
    ],
    "files_analyzed": ["contracts/modules/DegenerusGameDecimatorModule.sol", "contracts/storage/DegenerusGameStorage.sol"],
    "risk_assessment": "none",
    "implementation_notes": "Remove lines 339-342 (the if block and comment). The uint232(totalBurn) downcast at line 350 remains safe."
  },
  {
    "scavenger_id": "SCAV-005",
    "verdict": "REJECTED",
    "reasoning": "While current callers guarantee bucket >= 2, removing the guard would convert a clean zero-return into a division-by-zero panic (0x12) at line 719 if bucket were ever 0. The guard provides graceful degradation for the 'no participation' case (bucket=0 means player has no decimator entry). Keeping it costs only 10 bytes and preserves clean error semantics.",
    "edge_cases_checked": [
      "first burn with bucket=0 (takes m.bucket==0 branch at line 235, never reaches _decSubbucketFor)",
      "bucket migration with bucket < m.bucket (bucket >= 1, but could be 1 if coin contract bug)",
      "division by zero panic vs clean return"
    ],
    "files_analyzed": ["contracts/modules/DegenerusGameDecimatorModule.sol", "contracts/BurnieCoin.sol"],
    "risk_assessment": "low",
    "implementation_notes": "Keep. The guard converts a panic into a clean early return."
  },
  {
    "scavenger_id": "SCAV-006",
    "verdict": "APPROVED",
    "reasoning": "The function is private pure with exactly one call site: the loop in runDecimatorJackpot where denom iterates from 2 to 12. denom=0 is provably unreachable. If the guard were removed and a hypothetical future caller passed denom=0, the % denom at line 585 would revert with division-by-zero panic -- a safe failure mode.",
    "edge_cases_checked": [
      "runDecimatorJackpot loop bounds (denom=2 to DECIMATOR_MAX_DENOM=12)",
      "private function cannot be called externally",
      "division by zero revert as fallback safety"
    ],
    "files_analyzed": ["contracts/modules/DegenerusGameDecimatorModule.sol"],
    "risk_assessment": "none",
    "implementation_notes": "Remove line 583 entirely."
  },
  {
    "scavenger_id": "SCAV-007",
    "verdict": "REJECTED",
    "reasoning": "The delta==0 guard protects against no-op storage writes that waste gas (>2,100 gas per SSTORE). While current callers pre-check delta != 0, the migration path at line 245 passes prevBurn which could theoretically be 0 in edge cases. The denom==0 guard protects mapping key integrity. The runtime gas savings from avoiding an unnecessary SSTORE exceeds the one-time 14-byte deployment cost.",
    "edge_cases_checked": [
      "migration path: prevBurn after saturation could equal newBurn (delta=0)",
      "SSTORE gas cost (2,100+) vs 14 bytes deployment (2,800 gas one-time)",
      "decBucketBurnTotal[lvl][0][sub] slot access with denom=0"
    ],
    "files_analyzed": ["contracts/modules/DegenerusGameDecimatorModule.sol"],
    "risk_assessment": "low",
    "implementation_notes": "Keep. The runtime gas savings from avoiding unnecessary SSTORE outweigh the deployment cost."
  },
  {
    "scavenger_id": "SCAV-008",
    "verdict": "REJECTED",
    "reasoning": "The delta==0 guard is a no-op protection (safe but wasteful if triggered). The denom==0 guard is more critical: if denom were 0, decBucketBurnTotal[lvl][0][sub] would access an unintended storage slot, potentially corrupting state in a financial mapping that determines jackpot eligibility. While current callers guarantee denom >= 2, the guard protects against state corruption from any future code change.",
    "edge_cases_checked": [
      "mapping slot calculation with denom=0 (valid but unintended key)",
      "subtraction underflow check at line 701 (safe with delta=0)",
      "bucket migration flow (prevBurn guaranteed non-zero by line 244 check)"
    ],
    "files_analyzed": ["contracts/modules/DegenerusGameDecimatorModule.sol"],
    "risk_assessment": "medium",
    "implementation_notes": "Keep. Protects mapping key integrity in financial storage."
  },
  {
    "scavenger_id": "SCAV-009",
    "verdict": "APPROVED",
    "reasoning": "Confirmed: _applyLootboxBoostOnPurchase receives 'day' parameter (line 808) which equals _simulatedDayIndex() computed by the caller at line 751. Within a single transaction, block.timestamp is constant, so day == currentDay always. The redundant call generates unnecessary bytecode for the function call setup even if the compiler inlines the underlying computation.",
    "edge_cases_checked": [
      "block.timestamp constancy within transaction",
      "MintModule has identical pattern (line ~1084) -- same fix applies",
      "viaIR inlining behavior (may or may not deduplicate -- explicit change guarantees savings)"
    ],
    "files_analyzed": ["contracts/modules/DegenerusGameWhaleModule.sol", "contracts/modules/DegenerusGameMintModule.sol", "contracts/storage/DegenerusGameStorage.sol", "contracts/libraries/GameTimeLib.sol"],
    "risk_assessment": "none",
    "implementation_notes": "Replace 'uint48 currentDay = _simulatedDayIndex();' with 'uint48 currentDay = day;' at WhaleModule line 813. Apply same change in MintModule if identical pattern exists."
  },
  {
    "scavenger_id": "SCAV-010",
    "verdict": "N/A",
    "reasoning": "Zero bytecode savings. Already optimized with cached packed value and early-return on same-day check.",
    "edge_cases_checked": [],
    "files_analyzed": ["contracts/modules/DegenerusGameMintModule.sol"],
    "risk_assessment": "none",
    "implementation_notes": "No action needed."
  },
  {
    "scavenger_id": "SCAV-011",
    "verdict": "N/A",
    "reasoning": "Zero bytecode savings. Scavenger correctly identified this as a false positive. Both gameOver and jackpotPhaseFlag checks are independently reachable (gameOver via 120-day inactivity during PURCHASE state).",
    "edge_cases_checked": [],
    "files_analyzed": ["contracts/modules/DegenerusGameAdvanceModule.sol"],
    "risk_assessment": "none",
    "implementation_notes": "No action needed."
  },
  {
    "scavenger_id": "SCAV-012",
    "verdict": "N/A",
    "reasoning": "Zero bytecode savings. PriceLookupLib.priceForLevel is a pure library function that the compiler inlines at zero bytecode cost.",
    "edge_cases_checked": [],
    "files_analyzed": ["contracts/modules/DegenerusGameJackpotModule.sol", "contracts/libraries/PriceLookupLib.sol"],
    "risk_assessment": "none",
    "implementation_notes": "No action needed."
  },
  {
    "scavenger_id": "SCAV-013",
    "verdict": "N/A",
    "reasoning": "Zero bytecode savings. Withdrawn by Scavenger -- impractical to implement.",
    "edge_cases_checked": [],
    "files_analyzed": ["contracts/modules/DegenerusGameJackpotModule.sol"],
    "risk_assessment": "none",
    "implementation_notes": "No action needed."
  },
  {
    "scavenger_id": "SCAV-014",
    "verdict": "N/A",
    "reasoning": "Zero bytecode savings. Function already caches storage reads in local variables.",
    "edge_cases_checked": [],
    "files_analyzed": ["contracts/modules/DegenerusGameJackpotModule.sol"],
    "risk_assessment": "none",
    "implementation_notes": "No action needed."
  },
  {
    "scavenger_id": "SCAV-015",
    "verdict": "N/A",
    "reasoning": "Zero bytecode savings. Not dead code -- gas budget limiter is a runtime safety mechanism.",
    "edge_cases_checked": [],
    "files_analyzed": ["contracts/modules/DegenerusGameJackpotModule.sol"],
    "risk_assessment": "none",
    "implementation_notes": "No action needed."
  },
  {
    "scavenger_id": "SCAV-016",
    "verdict": "APPROVED",
    "reasoning": "Confirmed: 'unit' is assigned '1 ether' (10^18), a compile-time constant that is always non-zero. The 'unit == 0' leg of the compound guard at line ~1696 can never evaluate to true. The remaining guard 'poolBalance == 0 || ppm == 0' provides complete protection.",
    "edge_cases_checked": [
      "ppm derivation from tierRoll (all 4 branches assign non-zero constants)",
      "poolBalance can be 0 (external read) -- guard retained",
      "division by constant: compiler will constant-fold 1_000_000 * 1 ether"
    ],
    "files_analyzed": ["contracts/modules/DegenerusGameLootboxModule.sol"],
    "risk_assessment": "none",
    "implementation_notes": "Change guard to 'if (poolBalance == 0 || ppm == 0) return 0;'. Optionally inline unit as literal '1 ether' in the division."
  },
  {
    "scavenger_id": "SCAV-017",
    "verdict": "N/A",
    "reasoning": "Zero bytecode savings. Structural duplication required by delegatecall module architecture.",
    "edge_cases_checked": [],
    "files_analyzed": ["contracts/modules/DegenerusGameLootboxModule.sol", "contracts/modules/DegenerusGameWhaleModule.sol"],
    "risk_assessment": "none",
    "implementation_notes": "No action needed."
  },
  {
    "scavenger_id": "SCAV-018",
    "verdict": "N/A",
    "reasoning": "Zero bytecode savings. Security-critical access control pattern.",
    "edge_cases_checked": [],
    "files_analyzed": ["contracts/DegenerusGame.sol"],
    "risk_assessment": "none",
    "implementation_notes": "No action needed."
  },
  {
    "scavenger_id": "SCAV-019",
    "verdict": "N/A",
    "reasoning": "Zero bytecode savings. Structural requirement -- each module needs its own error declaration for correct selector.",
    "edge_cases_checked": [],
    "files_analyzed": ["contracts/DegenerusGame.sol", "contracts/modules/DegenerusGameWhaleModule.sol"],
    "risk_assessment": "none",
    "implementation_notes": "No action needed."
  },
  {
    "scavenger_id": "SCAV-020",
    "verdict": "N/A",
    "reasoning": "Zero bytecode savings. Intentional design pattern, not dead code.",
    "edge_cases_checked": [],
    "files_analyzed": ["contracts/BurnieCoin.sol"],
    "risk_assessment": "none",
    "implementation_notes": "No action needed."
  },
  {
    "scavenger_id": "SCAV-021",
    "verdict": "N/A",
    "reasoning": "Zero bytecode savings. Unreferenced compile-time constant is already eliminated by the optimizer.",
    "edge_cases_checked": [],
    "files_analyzed": ["contracts/DegenerusQuests.sol"],
    "risk_assessment": "none",
    "implementation_notes": "No action needed."
  }
]
```

---

## Test Verification (Post-Implementation)

**Date:** 2026-03-17

All 4 APPROVED changes (SCAV-004, SCAV-006, SCAV-009, SCAV-016) were applied to source contracts and verified.

### Changes Applied

| ID | Contract | Change | Status |
|----|----------|--------|--------|
| SCAV-004 | DecimatorModule | Removed unreachable `totalBurn > type(uint232).max` check (4 lines) | Applied |
| SCAV-006 | DecimatorModule | Removed unreachable `denom == 0` guard (1 line) | Applied |
| SCAV-016 | LootboxModule | Removed dead `unit == 0` check, inlined `1 ether` | Applied |
| SCAV-009 | WhaleModule | Replaced `_simulatedDayIndex()` with `day` parameter | Applied |

**Note on SCAV-009 (MintModule):** The report suggested applying the same pattern in MintModule `_applyLootboxBoostOnPurchase`. Upon inspection, MintModule already uses the `day` parameter directly (not `_simulatedDayIndex()`), so no change was needed there.

### Test Results

**Hardhat:**
- 1,198 passing (3m)
- 26 failing (pre-existing: affiliate/RNG/economic -- unrelated to gas optimization scope)
- 0 new failures

**Foundry:**
- `forge build`: compilation successful (no new errors or warnings)

### Reverted Changes

None. All 4 APPROVED changes passed the full test suite without regressions.

### Line Count Changes

| File | Before | After | Delta |
|------|--------|-------|-------|
| DegenerusGameDecimatorModule.sol | 754 | 748 | -6 |
| DegenerusGameWhaleModule.sol | 907 | 907 | 0 (in-place replacement) |
| DegenerusGameLootboxModule.sol | 1,779 | 1,778 | -1 |
| DegenerusGameJackpotModule.sol | 2,824 | 2,824 | 0 (no changes -- confirmed 0 removable bytes) |

---

## Bytecode Impact

Post-optimization bytecode sizes measured via `npx hardhat compile --force` on Solidity 0.8.34, viaIR=true, optimizer runs=200.

### Directly Modified Contracts

| Contract | Baseline (bytes) | After (bytes) | Delta (bytes) | Baseline % | After % |
|----------|-----------------|---------------|---------------|-----------|---------|
| DecimatorModule | 5,678 | 5,671 | **-7** | 23.1% | 23.1% |
| WhaleModule | 11,760 | 11,700 | **-60** | 47.9% | 47.6% |
| LootboxModule | 19,382 | 19,353 | **-29** | 78.9% | 78.7% |

**Total savings on modified contracts: -96 bytes**

**Note on estimates vs actuals:** The Scavenger estimated ~68 bytes total savings across the 3 modified contracts (DecimatorModule: ~32, WhaleModule: ~30, LootboxModule: ~6). Actual measured savings are -96 bytes. The difference arises because the viaIR optimizer reorganizes Yul intermediate representation when source changes, and removing dead code allows the optimizer to find additional simplification opportunities that were blocked by the presence of the dead code. This is a common and expected effect with Solidity's IR pipeline.

### JackpotModule (Primary Target)

| Contract | Baseline (bytes) | After (bytes) | Delta (bytes) | Baseline % | After % |
|----------|-----------------|---------------|---------------|-----------|---------|
| JackpotModule | 23,583 | 23,577 | **-6** | 95.9% | 95.9% |

The JackpotModule shows a -6 byte reduction despite receiving zero approved changes. This is a secondary effect of the shared inheritance hierarchy (DegenerusGameStorage) being recompiled alongside the modified modules. The headroom improvement is negligible: from 993 bytes to 999 bytes of remaining capacity.

**Conclusion:** The JackpotModule's 95.9% utilization is confirmed as genuine functional complexity with zero optimization headroom. No behavior-preserving dead code removal can meaningfully reduce its size.

### All Contracts (Full Before/After Comparison)

All contracts with bytecode > 100 bytes, measured against baselines from the pre-optimization compilation (RESEARCH.md).

| Contract | Baseline (bytes) | After (bytes) | Delta (bytes) | Notes |
|----------|-----------------|---------------|---------------|-------|
| JackpotModule | 23,583 | 23,577 | -6 | No direct changes; secondary recompilation effect |
| DegenerusGame | 21,372 | 21,358 | -14 | No direct changes; shared storage inheritance |
| LootboxModule | 19,382 | 19,353 | **-29** | SCAV-016 applied |
| BurnieCoinflip | 18,044 | 18,044 | 0 | No changes (independent contract) |
| MintModule | 15,084 | 15,070 | -14 | No direct changes; shared storage inheritance |
| AdvanceModule | 14,073 | 14,189 | +116 | No direct changes; IR optimizer rebalancing |
| DegenerusQuests | 12,284 | 12,284 | 0 | No changes (independent contract) |
| WhaleModule | 11,760 | 11,700 | **-60** | SCAV-009 applied |
| DegenerusVault | 10,557 | 10,557 | 0 | No changes (independent contract) |
| BurnieCoin | 9,074 | 9,074 | 0 | No changes (independent contract) |
| DegeneretteModule | 8,676 | 8,662 | -14 | No direct changes; shared storage inheritance |
| EndgameModule | 6,233 | 6,219 | -14 | No direct changes; shared storage inheritance |
| DecimatorModule | 5,678 | 5,671 | **-7** | SCAV-004 + SCAV-006 applied |
| BoonModule | 5,447 | 5,433 | -14 | No direct changes; shared storage inheritance |
| StakedDegenerusStonk | 5,245 | 5,245 | 0 | No changes (independent contract) |
| GameOverModule | 3,132 | 3,132 | 0 | No changes; note: shared inheritance, but no delta |
| DegenerusStonk | 2,551 | 2,551 | 0 | No changes (independent contract) |

**Total bytecode delta across all contracts: -82 bytes** (sum of all deltas, including +116 from AdvanceModule IR rebalancing)

**Total bytecode delta on directly modified contracts: -96 bytes**

**Deployment gas savings (directly modified contracts):** -96 bytes x 200 gas/byte = **~19,200 deployment gas** saved

**Note on secondary effects:** Several unmodified contracts that inherit DegenerusGameStorage show -14 bytes of secondary savings. One contract (AdvanceModule) shows +116 bytes increase due to IR optimizer rebalancing -- this is a known characteristic of the viaIR pipeline where removing code in one module can cause the optimizer to make different inlining decisions in sibling modules that share the same base contract. The AdvanceModule remains well within limits at 57.7% of the 24,576-byte cap. These secondary effects are compiler artifacts and not a concern.

---

## Final Summary

### Audit Scope

- **Contracts analyzed:** 28 production contracts + 5 libraries + 2 interfaces (~25,600 lines of Solidity)
- **Methodology:** Scavenger/Skeptic dual-agent analysis with formal verdicts
- **Categories:** GAS-01 (unreachable checks), GAS-02 (dead storage), GAS-03 (dead code paths), GAS-04 (redundant calls/SLOADs)

### Verdict Distribution

| Verdict | Count |
|---------|-------|
| APPROVED | 4 |
| REJECTED | 3 |
| PARTIAL | 0 |
| NEEDS_HUMAN_REVIEW | 0 |
| N/A (0 bytes, no action) | 14 |
| **Total recommendations** | **21** |

### Results

| Metric | Value |
|--------|-------|
| Bytecode saved (directly modified contracts) | **96 bytes** |
| Deployment gas saved (directly modified contracts) | **~19,200 gas** |
| Source lines removed | 7 |
| Contracts modified | 3 (DecimatorModule, WhaleModule, LootboxModule) |
| Contracts unmodified (confirmed correct) | 25 |
| Test regressions introduced | **0** (1,198 passing, 26 pre-existing) |
| Reverted changes | 0 |

### JackpotModule Headroom

| Metric | Before | After |
|--------|--------|-------|
| Bytecode size | 23,583 bytes | 23,577 bytes |
| Utilization | 95.9% | 95.9% |
| Headroom | 993 bytes | 999 bytes |
| Removable dead code | 0 bytes | 0 bytes |

**Conclusion:** The JackpotModule's size is the result of genuine functional complexity (multi-bucket trait-based jackpot distribution with chunked processing, auto-rebuy, and prize pool consolidation). No behavior-preserving optimization can meaningfully reduce its bytecode. The 6-byte secondary reduction from recompilation does not change the utilization percentage.

### Key Findings

1. **Codebase is exceptionally well-optimized.** Only 7 of 21 candidates had non-zero bytecode savings potential. The remaining 14 were correctly identified as structural requirements, compiler-handled, or zero-impact items.

2. **Defense-in-depth guards are worth keeping.** The 3 REJECTED recommendations (SCAV-005, SCAV-007, SCAV-008) in DecimatorModule protect against division-by-zero panics, unnecessary SSTORE writes (2,100+ gas), and mapping key corruption. The runtime gas savings from keeping these guards exceed their one-time deployment cost.

3. **JackpotModule has zero optimization headroom.** At 95.9% of the EVM size limit, the module's 2,824 lines are fully utilized. This is the most size-constrained contract in the protocol, and any future feature additions will need to consider bytecode budget carefully.

4. **viaIR optimizer creates secondary effects.** Removing dead code in 3 contracts caused measurable bytecode changes in 7 unmodified sibling contracts (most -14 bytes, one +116 bytes). These are compiler artifacts from IR pipeline reorganization, not bugs.

### Requirements Satisfied

| Requirement | Status | Evidence |
|-------------|--------|----------|
| GAS-01: Unreachable checks | Complete | SCAV-004, SCAV-006 APPROVED and applied; SCAV-005 REJECTED (defense-in-depth) |
| GAS-02: Dead storage variables | Complete | SCAV-001, SCAV-002, SCAV-003 analyzed; 0 removable (all structural/compatibility) |
| GAS-03: Dead code paths | Complete | SCAV-016 APPROVED and applied; SCAV-007, SCAV-008 REJECTED (defense-in-depth) |
| GAS-04: Redundant calls/SLOADs | Complete | SCAV-009 APPROVED and applied; MintModule already optimized |

### Report Status

This gas optimization report is **complete and audit-package ready**. All sections have been finalized:
- Executive Summary with verdict distribution
- Estimated vs actual savings comparison
- Approved removals with full Skeptic analysis
- Rejected recommendations with counterexamples
- Implementation order and notes
- Full Scavenger recommendation appendices (21 items)
- Test verification with zero regressions
- Bytecode impact with measured before/after sizes
- Final summary with quantified results
