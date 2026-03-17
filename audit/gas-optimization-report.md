# Gas Optimization Report: Scavenger/Skeptic Dual-Agent Audit

**Protocol:** Degenerus Protocol (v2.0)
**Compiler:** Solidity 0.8.34, viaIR=true, optimizer runs=200
**Scope:** ~25,600 lines across 28 production contracts + 5 libraries + 2 interfaces
**Date:** 2026-03-17

---

## Scavenger Recommendations

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

**Note:** Already optimized. No action needed.

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

**Note:** Both checks are necessary. False positive -- withdrawn.

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

**Note:** Compiler likely inlines pure library calls. Minimal savings.

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

**Note:** Theoretical savings. Impractical to implement. Withdrawn.

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

**Note:** Already uses local variables for caching. No action needed.

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

**Note:** Not dead code. Withdrawn.

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

**Note:** Structural duplication required by delegatecall architecture. No action.

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

**Note:** Security-critical. No action.

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

**Note:** Structural requirement. No action.

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

**Note:** No action needed. Not dead code.

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

**Note:** Already optimized away by compiler. No action needed.

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

## Summary of Scavenger Findings

| ID | Contract | Type | Category | Confidence | Bytecode Savings |
|----|----------|------|----------|------------|-----------------|
| SCAV-001 | Storage | unused_storage_slot | GAS-02 | high | 0 bytes (slot alignment) |
| SCAV-002 | Storage | unused_storage_slot | GAS-02 | high | 0 bytes (struct packing) |
| SCAV-003 | BitPackingLib | unused_variable | GAS-02 | high | 0 bytes (comments only) |
| SCAV-004 | DecimatorModule | defensive_check_impossible | GAS-01 | high | 22 bytes |
| SCAV-005 | DecimatorModule | defensive_check_impossible | GAS-01 | medium | 10 bytes |
| SCAV-006 | DecimatorModule | defensive_check_impossible | GAS-01 | high | 10 bytes |
| SCAV-007 | DecimatorModule | defensive_check_impossible | GAS-01 | medium | 14 bytes |
| SCAV-008 | DecimatorModule | defensive_check_impossible | GAS-01 | medium | 14 bytes |
| SCAV-009 | WhaleModule | redundant_sload | GAS-04 | low | 30 bytes |
| SCAV-010 | MintModule | redundant_sload | GAS-04 | low | 0 bytes (already optimized) |
| SCAV-011 | AdvanceModule | redundant_require | GAS-01 | low | 0 bytes (false positive) |
| SCAV-012 | JackpotModule | redundant_external_call | GAS-04 | low | 0 bytes (compiler inlines) |
| SCAV-013 | JackpotModule | redundant_sload | GAS-04 | low | 0 bytes (withdrawn) |
| SCAV-014 | JackpotModule | redundant_sload | GAS-04 | low | 0 bytes (already cached) |
| SCAV-015 | JackpotModule | dead_code_path | GAS-03 | low | 0 bytes (not dead code) |
| SCAV-016 | LootboxModule | dead_code_path | GAS-03 | high | 6 bytes |
| SCAV-017 | LootboxModule | dead_code_path | GAS-03 | low | 0 bytes (structural) |
| SCAV-018 | DegenerusGame | redundant_sload | GAS-04 | low | 0 bytes (security-critical) |
| SCAV-019 | DegenerusGame | dead_code_path | GAS-03 | low | 0 bytes (structural) |
| SCAV-020 | BurnieCoin | redundant_require | GAS-01 | low | 0 bytes (not dead code) |
| SCAV-021 | Quests | unused_variable | GAS-02 | high | 0 bytes (compiler eliminates) |

### JackpotModule Priority Summary

**Current bytecode:** 23,583 / 24,576 bytes (95.9%)

**Potential Scavenger savings in JackpotModule: 0 bytes**

The JackpotModule was analyzed thoroughly (all 2,824 lines). No dead code, unreachable branches, or removable checks were found. The module is extremely tight -- every function is called during the jackpot distribution flow, every branch is reachable through the game state machine (daily jackpots, BAF/Decimator transitions, century levels, compressed vs normal mode, terminal jackpot). The viaIR optimizer with 200 runs already handles local SLOAD caching and pure function inlining.

The 95.9% size utilization is a result of genuine functional complexity (multi-bucket trait-based jackpot distribution with chunked processing, auto-rebuy, prize pool consolidation, and pool snapshot accounting), not of waste code.

### Candidates for Actual Removal (Non-Zero Savings)

Only these recommendations have non-zero bytecode savings potential:

| ID | Contract | Bytes Saved | Gas Saved | Description |
|----|----------|-------------|-----------|-------------|
| SCAV-004 | DecimatorModule | ~22 | ~4,400 | Remove `totalBurn > uint232.max` defensive check |
| SCAV-005 | DecimatorModule | ~10 | ~2,000 | Remove `bucket == 0` guard in `_decSubbucketFor` |
| SCAV-006 | DecimatorModule | ~10 | ~2,000 | Remove `denom == 0` guard in `_decWinningSubbucket` |
| SCAV-007 | DecimatorModule | ~14 | ~2,800 | Remove `delta == 0 || denom == 0` in `_decUpdateSubbucket` |
| SCAV-008 | DecimatorModule | ~14 | ~2,800 | Remove `delta == 0 || denom == 0` in `_decRemoveSubbucket` |
| SCAV-009 | WhaleModule | ~30 | ~6,000 | Cache `_simulatedDayIndex()` result from caller |
| SCAV-016 | LootboxModule | ~6 | ~1,200 | Remove `unit == 0` from compound guard |

**Total potential savings: ~106 bytes bytecode, ~21,200 deployment gas**

None of these savings apply to JackpotModule (the priority contract at 95.9% of size limit).
