# Support Contracts -- Function-Level Audit

**Contracts:** DegenerusTraitUtils, ContractAddresses, Icons32Data
**Audit date:** 2026-03-07
**Auditor:** Phase 56 Plan 03

---

## Part 1: DegenerusTraitUtils.sol

**File:** contracts/DegenerusTraitUtils.sol
**Lines:** 184
**Solidity:** 0.8.34
**Type:** Internal pure library (no state, no external calls)

### Summary

Deterministic trait generation from 256-bit random seeds. Produces 32-bit packed trait values encoding 4 independent trait IDs (one per quadrant A-D). Each 8-bit trait ID encodes: quadrant (2 bits), category bucket (3 bits), sub-bucket (3 bits). Weighted distribution assigns higher probability to lower buckets (13.3% each for 0-3, 12.0% for 4-6, 10.7% for bucket 7).

### Function Audit

### `weightedBucket(uint32 rnd)` [internal pure]

| Field | Value |
|-------|-------|
| **Signature** | `function weightedBucket(uint32 rnd) internal pure returns (uint8)` |
| **Visibility** | internal |
| **Mutability** | pure |
| **Parameters** | `rnd` (uint32): 32-bit random input value |
| **Returns** | `uint8`: Bucket index 0-7 with weighted distribution |

**State Reads:** None (pure)
**State Writes:** None (pure)

**Callers:** `traitFromWord` (called twice per invocation -- once for category, once for sub-bucket)
**Callees:** None

**ETH Flow:** None
**Invariants:**
- Output is always in [0, 7]
- Same input always produces same output (deterministic)
- Distribution is weighted: buckets 0-3 get ~13.3% each, 4-6 get ~12.0% each, 7 gets ~10.7%

**Mathematical Verification:**

Scaling: `uint32((uint64(rnd) * 75) >> 32)`
- Input range: rnd in [0, 2^32 - 1]
- `uint64(rnd) * 75`: max = (2^32 - 1) * 75 = 322,122,547,125 which fits in uint64 (max 2^64 - 1)
- `>> 32` divides by 2^32: result range = [0, floor((2^32 - 1) * 75 / 2^32)] = [0, 74]
- All 75 values (0-74) are reachable

Bucket assignment:
| Bucket | Range   | Width | Probability (width/75) |
|--------|---------|-------|------------------------|
| 0      | 0-9     | 10    | 13.33% |
| 1      | 10-19   | 10    | 13.33% |
| 2      | 20-29   | 10    | 13.33% |
| 3      | 30-39   | 10    | 13.33% |
| 4      | 40-48   | 9     | 12.00% |
| 5      | 49-57   | 9     | 12.00% |
| 6      | 58-66   | 9     | 12.00% |
| 7      | 67-74   | 8     | 10.67% |
| **Sum** |        | **75**| **100%** |

Coverage check: 10+10+10+10+9+9+9+8 = 75. Complete coverage of [0, 74] with no gaps or overlaps.

**Unchecked Safety:** The `unchecked` block is safe because:
1. `uint64(rnd) * 75` cannot overflow uint64 (max product ~322B vs uint64 max ~18.4E18)
2. Right-shift by 32 produces [0, 74], all comparison operations are safe
3. No subtraction or division that could underflow

**NatSpec Accuracy:** NatSpec matches behavior exactly. Bucket thresholds in documentation match code.
**Gas Flags:** None. Linear if-chain is gas-optimal for 8 buckets (average 4 comparisons).
**Verdict:** CORRECT

---

### `traitFromWord(uint64 rnd)` [internal pure]

| Field | Value |
|-------|-------|
| **Signature** | `function traitFromWord(uint64 rnd) internal pure returns (uint8)` |
| **Visibility** | internal |
| **Mutability** | pure |
| **Parameters** | `rnd` (uint64): 64-bit random input value |
| **Returns** | `uint8`: 6-bit trait ID (0-63, quadrant bits not included) |

**State Reads:** None (pure)
**State Writes:** None (pure)

**Callers:** `packedTraitsFromSeed` (called 4 times), also called directly by:
- `DegenerusGameMintModule._traitSample` (line 467): `DegenerusTraitUtils.traitFromWord(s) + (uint8(i & 3) << 6)`
- `DegenerusGameJackpotModule` (line 2180): `DegenerusTraitUtils.traitFromWord(s) + ...`
**Callees:** `weightedBucket` (called twice)

**ETH Flow:** None
**Invariants:**
- Output is always in [0, 63] (6 bits: 3 category + 3 sub-bucket)
- Same input always produces same output (deterministic)
- Category and sub-bucket are independently weighted

**Mathematical Verification:**

Bit decomposition:
- `uint32(rnd)`: extracts low 32 bits for category bucket
- `uint32(rnd >> 32)`: extracts high 32 bits for sub-bucket
- Both halves are independently processed through `weightedBucket` -> each in [0, 7]

Combination: `(category << 3) | sub`
- category in [0, 7] -> `category << 3` in {0, 8, 16, 24, 32, 40, 48, 56}
- sub in [0, 7]
- OR produces: category*8 + sub, range [0, 63]
- No bit overlap: category occupies bits [5:3], sub occupies bits [2:0]

**NatSpec Accuracy:** NatSpec says "6-bit trait ID (0-63, quadrant bits not included)" -- correct. Output format [CCC][SSS] matches code.
**Gas Flags:** None.
**Verdict:** CORRECT

---

### `packedTraitsFromSeed(uint256 rand)` [internal pure]

| Field | Value |
|-------|-------|
| **Signature** | `function packedTraitsFromSeed(uint256 rand) internal pure returns (uint32)` |
| **Visibility** | internal |
| **Mutability** | pure |
| **Parameters** | `rand` (uint256): 256-bit random seed (typically from keccak256) |
| **Returns** | `uint32`: 32-bit packed traits value |

**State Reads:** None (pure)
**State Writes:** None (pure)

**Callers:**
- `DegenerusGameDegeneretteModule` (line 644): `DegenerusTraitUtils.packedTraitsFromSeed(resultSeed)`
**Callees:** `traitFromWord` (called 4 times)

**ETH Flow:** None
**Invariants:**
- Same input seed always produces same 32-bit output (deterministic)
- Each 8-bit trait encodes [QQ][CCC][SSS] where QQ = quadrant, CCC = category, SSS = sub-bucket
- Four traits are independently generated from non-overlapping 64-bit seed segments

**Mathematical Verification:**

Seed decomposition:
- `uint64(rand)`: bits [63:0] -> Trait A (quadrant 0)
- `uint64(rand >> 64)`: bits [127:64] -> Trait B (quadrant 1)
- `uint64(rand >> 128)`: bits [191:128] -> Trait C (quadrant 2)
- `uint64(rand >> 192)`: bits [255:192] -> Trait D (quadrant 3)

Quadrant tagging:
- traitA: no OR (quadrant 0 = 0b00 in bits [7:6]) -> range [0, 63]
- traitB: OR with 64 (0b01_000000) -> range [64, 127]
- traitC: OR with 128 (0b10_000000) -> range [128, 191]
- traitD: OR with 192 (0b11_000000) -> range [192, 255]

Packing: `uint32(traitA) | (uint32(traitB) << 8) | (uint32(traitC) << 16) | (uint32(traitD) << 24)`
- traitA in byte 0 (bits [7:0])
- traitB in byte 1 (bits [15:8])
- traitC in byte 2 (bits [23:16])
- traitD in byte 3 (bits [31:24])
- No overlap: each trait occupies exactly one byte

**NatSpec Accuracy:** NatSpec matches implementation. Seed usage diagram is correct. Output format [traitD:8][traitC:8][traitB:8][traitA:8] matches little-endian packing.
**Gas Flags:** None. Efficient use of bit operations.
**Verdict:** CORRECT

---

## Part 2: ContractAddresses.sol

**File:** contracts/ContractAddresses.sol
**Lines:** 39
**Solidity:** ^0.8.26
**Type:** Library with compile-time constants

### Summary

Central address registry for the Degenerus protocol. Contains 28 `internal constant` values (26 addresses, 1 uint48, 1 bytes32) all set to zero in source. The deploy pipeline (`scripts/lib/patchContractAddresses.js`) patches this file with nonce-predicted addresses before compilation. Every contract in the protocol imports this library for cross-contract resolution.

### Constants Verification

| # | Constant | Type | Category | Deploy Order (N+offset) | Verified |
|---|----------|------|----------|-------------------------|----------|
| 1 | `DEPLOY_DAY_BOUNDARY` | uint48 | Config | N/A (computed from deploy timestamp) | CORRECT |
| 2 | `VRF_KEY_HASH` | bytes32 | Config | N/A (Chainlink VRF key hash) | CORRECT |
| 3 | `ICONS_32` | address | Deployable | N+0 | CORRECT |
| 4 | `GAME_MINT_MODULE` | address | Module | N+1 | CORRECT |
| 5 | `GAME_ADVANCE_MODULE` | address | Module | N+2 | CORRECT |
| 6 | `GAME_WHALE_MODULE` | address | Module | N+3 | CORRECT |
| 7 | `GAME_JACKPOT_MODULE` | address | Module | N+4 | CORRECT |
| 8 | `GAME_DECIMATOR_MODULE` | address | Module | N+5 | CORRECT |
| 9 | `GAME_ENDGAME_MODULE` | address | Module | N+6 | CORRECT |
| 10 | `GAME_GAMEOVER_MODULE` | address | Module | N+7 | CORRECT |
| 11 | `GAME_LOOTBOX_MODULE` | address | Module | N+8 | CORRECT |
| 12 | `GAME_BOON_MODULE` | address | Module | N+9 | CORRECT |
| 13 | `GAME_DEGENERETTE_MODULE` | address | Module | N+10 | CORRECT |
| 14 | `COIN` | address | Core | N+11 | CORRECT |
| 15 | `COINFLIP` | address | Core | N+12 | CORRECT |
| 16 | `GAME` | address | Core | N+13 | CORRECT |
| 17 | `DGNRS` | address | Core | N+20 (Stonk) | CORRECT |
| 18 | `ADMIN` | address | Core | N+21 | CORRECT |
| 19 | `VAULT` | address | Core | N+19 | CORRECT |
| 20 | `AFFILIATE` | address | Core | N+15 | CORRECT |
| 21 | `JACKPOTS` | address | Core | N+16 | CORRECT |
| 22 | `QUESTS` | address | Core | N+17 | CORRECT |
| 23 | `DEITY_PASS` | address | Core | N+18 | CORRECT |
| 24 | `WWXRP` | address | Core | N+14 | CORRECT |
| 25 | `STETH_TOKEN` | address | External | N/A (Lido stETH mainnet: 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84) | CORRECT |
| 26 | `LINK_TOKEN` | address | External | N/A (Chainlink LINK mainnet: 0x514910771AF9Ca656af840dff83E8264EcF986CA) | CORRECT |
| 27 | `CREATOR` | address | External | N/A (deployer EOA) | CORRECT |
| 28 | `VRF_COORDINATOR` | address | External | N/A (Chainlink VRF V2.5: 0x271682DEB8C4E0901D1a1550aD2e64D568E69909) | CORRECT |
| 29 | `WXRP` | address | External | N/A (underlying XRP token) | CORRECT |

Note: 29 total entries (2 non-address config + 22 deployable addresses + 5 external addresses). The plan stated 28 constants; actual count is 29.

### Deploy Order Cross-Reference

ContractAddresses.sol constants (lines 11-37) exactly match DEPLOY_ORDER in `predictAddresses.js` (lines 16-38):

| Source Order (ContractAddresses.sol) | DEPLOY_ORDER Index | Match |
|--------------------------------------|--------------------|-------|
| ICONS_32 (line 11) | [0] N+0 | Yes |
| GAME_MINT_MODULE (line 12) | [1] N+1 | Yes |
| GAME_ADVANCE_MODULE (line 13) | [2] N+2 | Yes |
| GAME_WHALE_MODULE (line 14) | [3] N+3 | Yes |
| GAME_JACKPOT_MODULE (line 15) | [4] N+4 | Yes |
| GAME_DECIMATOR_MODULE (line 16) | [5] N+5 | Yes |
| GAME_ENDGAME_MODULE (line 17) | [6] N+6 | Yes |
| GAME_GAMEOVER_MODULE (line 18) | [7] N+7 | Yes |
| GAME_LOOTBOX_MODULE (line 19) | [8] N+8 | Yes |
| GAME_BOON_MODULE (line 20) | [9] N+9 | Yes |
| GAME_DEGENERETTE_MODULE (line 21) | [10] N+10 | Yes |
| COIN (line 22) | [11] N+11 | Yes |
| COINFLIP (line 23) | [12] N+12 | Yes |
| GAME (line 28) | [13] N+13 | Yes |
| WWXRP (line 32) | [14] N+14 | Yes |
| AFFILIATE (line 25) | [15] N+15 | Yes |
| JACKPOTS (line 26) | [16] N+16 | Yes |
| QUESTS (line 27) | [17] N+17 | Yes |
| DEITY_PASS (line 31) | [18] N+18 | Yes |
| VAULT (line 24) | [19] N+19 | Yes |
| DGNRS (line 29) | [20] N+20 | Yes |
| ADMIN (line 30) | [21] N+21 | Yes |

All 22 deployable constants match DEPLOY_ORDER. Note that ContractAddresses.sol lists them in a different order than DEPLOY_ORDER (grouped by category rather than deploy sequence), but the patch script uses key-based lookup so order within the file is irrelevant.

### Deploy Order Dependency Verification

| Dependency Rule | Constraint | DEPLOY_ORDER | Verified |
|-----------------|------------|--------------|----------|
| VAULT after COIN | VAULT calls `COIN.vaultMintAllowance()` in constructor | COIN=N+11, VAULT=N+19 | CORRECT |
| DGNRS after GAME+modules | DGNRS calls `GAME.claimWhalePass()` / `GAME.setAfKingMode()` | Modules=N+0..10, GAME=N+13, DGNRS=N+20 | CORRECT |
| ADMIN after GAME | ADMIN calls `GAME.wireVrf()` | GAME=N+13, ADMIN=N+21 | CORRECT |
| DEITY_PASS before DGNRS | No constructor dependency; DEITY_PASS=N+18 deployed before DGNRS=N+20 | CORRECT |
| All modules before GAME | Modules N+0..10 deployed before GAME N+13 | CORRECT |

### Source Format Notes

- All address constants set to `address(0)` in source
- `DEPLOY_DAY_BOUNDARY` set to `0` in source
- `VRF_KEY_HASH` set to `bytes32(0)` in source
- Deploy pipeline patches with live values before compilation
- Solidity version `^0.8.26` (floating) is compatible with all importing contracts (0.8.26 and 0.8.34)

**NatSpec Accuracy:** Minimal NatSpec -- only a file-level comment explaining the pattern. Adequate for a constants-only library.
**Verdict:** CORRECT -- All 29 constants verified against deploy order and cross-contract usage.

---

## Part 3: Icons32Data.sol

**File:** contracts/Icons32Data.sol
**Lines:** 229
**Solidity:** 0.8.34
**Type:** Concrete contract (on-chain data storage with finalization lifecycle)

### Summary

On-chain SVG path storage for 33 icons (32 quadrant symbols + 1 affiliate badge) plus symbol name arrays for 3 quadrants (8 names each). Mutable lifecycle until `finalize()` is called by CREATOR, after which all data becomes permanently immutable. Used exclusively by DegenerusDeityPass for on-chain SVG rendering via `data(i)` and `symbol(q, idx)` view functions.

### Function Audit

### `constructor()` [public]

| Field | Value |
|-------|-------|
| **Signature** | `constructor()` |
| **Visibility** | public (implicit) |
| **Mutability** | state-changing |
| **Parameters** | None |
| **Returns** | N/A |

**State Reads:** None
**State Writes:** None (empty constructor; storage defaults to zero/empty/false)

**Callers:** Deploy script
**Callees:** None

**ETH Flow:** None
**Invariants:** After construction, `_finalized` is `false`, all paths are empty strings, all symbol arrays are empty.
**NatSpec Accuracy:** NatSpec says "Deploy contract for batch initialization by CREATOR" -- correct.
**Gas Flags:** None. Empty constructor is minimal gas.
**Verdict:** CORRECT

---

### `setPaths(uint256 startIndex, string[] calldata paths)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function setPaths(uint256 startIndex, string[] calldata paths) external` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `startIndex` (uint256): Starting index in _paths array (0-32); `paths` (string[]): Array of SVG path strings (max 10) |
| **Returns** | None |

**State Reads:** `_finalized`
**State Writes:** `_paths[startIndex]` through `_paths[startIndex + paths.length - 1]`

**Callers:** CREATOR (off-chain, during initialization)
**Callees:** None

**ETH Flow:** None
**Invariants:**
- Only callable when `msg.sender == ContractAddresses.CREATOR`
- Only callable when `_finalized == false`
- `paths.length <= 10` (batch size cap)
- `startIndex + paths.length <= 33` (bounds check)

**Access Control Verification:**
1. `if (msg.sender != ContractAddresses.CREATOR) revert OnlyCreator();` -- CREATOR-only
2. `if (_finalized) revert AlreadyFinalized();` -- pre-finalization only
3. `if (paths.length > 10) revert MaxBatch();` -- batch size limit
4. `if (startIndex + paths.length > 33) revert IndexOutOfBounds();` -- bounds check

**Overflow Analysis:** `startIndex + paths.length` -- since `paths.length <= 10` and `startIndex` is uint256, addition cannot overflow in practice (would require startIndex near 2^256). The `> 33` check ensures array bounds are respected.

**NatSpec Accuracy:** NatSpec matches behavior. Documents all 4 revert conditions.
**Gas Flags:** None. Loop is bounded by batch size (max 10 iterations).
**Verdict:** CORRECT

---

### `setSymbols(uint256 quadrant, string[8] memory symbols)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function setSymbols(uint256 quadrant, string[8] memory symbols) external` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `quadrant` (uint256): Quadrant number (1=Crypto, 2=Zodiac, 3=Cards); `symbols` (string[8]): Array of 8 symbol names |
| **Returns** | None |

**State Reads:** `_finalized`
**State Writes:** `_symQ1[0..7]` or `_symQ2[0..7]` or `_symQ3[0..7]` depending on quadrant

**Callers:** CREATOR (off-chain, during initialization)
**Callees:** None

**ETH Flow:** None
**Invariants:**
- Only callable when `msg.sender == ContractAddresses.CREATOR`
- Only callable when `_finalized == false`
- `quadrant` must be 1, 2, or 3

**Access Control Verification:**
1. `if (msg.sender != ContractAddresses.CREATOR) revert OnlyCreator();` -- CREATOR-only
2. `if (_finalized) revert AlreadyFinalized();` -- pre-finalization only
3. Quadrant validation: if-else chain with `revert InvalidQuadrant()` for values outside {1, 2, 3}

**NatSpec Discrepancy:** NatSpec says "Quadrant 0 (Dice) names are generated dynamically" but the setter maps quadrant 1=Crypto, 2=Zodiac, 3=Cards. The storage variables are `_symQ1`, `_symQ2`, `_symQ3`, which suggests the naming convention uses 1-indexed quadrants for setters while the `symbol()` view function uses 0-indexed quadrants. This is a minor naming inconsistency but functionally correct:
- `setSymbols(1, ...)` writes to `_symQ1` (Crypto) -> read via `symbol(0, idx)` returns `_symQ1[idx]`
- `setSymbols(2, ...)` writes to `_symQ2` (Zodiac) -> read via `symbol(1, idx)` returns `_symQ2[idx]`
- `setSymbols(3, ...)` writes to `_symQ3` (Cards) -> read via `symbol(2, idx)` returns `_symQ3[idx]`

The 1-indexed setter vs 0-indexed getter is an intentional design: Dice (quadrant 3 in getter, absent from setter) generates names dynamically.

**Gas Flags:** None. Fixed 8-iteration loop.
**Verdict:** CORRECT (with informational note on 1-indexed setter vs 0-indexed getter naming)

---

### `finalize()` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function finalize() external` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | None |
| **Returns** | None |

**State Reads:** `_finalized`
**State Writes:** `_finalized = true`

**Callers:** CREATOR (off-chain, after all data is populated)
**Callees:** None

**ETH Flow:** None
**Invariants:**
- Only callable when `msg.sender == ContractAddresses.CREATOR`
- Only callable when `_finalized == false`
- After execution, `_finalized == true` (permanent, irreversible)
- Once finalized, setPaths and setSymbols will always revert

**Access Control Verification:**
1. `if (msg.sender != ContractAddresses.CREATOR) revert OnlyCreator();` -- CREATOR-only
2. `if (_finalized) revert AlreadyFinalized();` -- single-use

**Finalization Lifecycle:**
```
MUTABLE (deployed) --[finalize()]--> IMMUTABLE (permanent)
```
There is no `unfinalize()` or admin override. Once `_finalized = true`, it cannot be reversed.

**NatSpec Accuracy:** NatSpec says "Finalize the contract, locking all data permanently" and "Only callable by CREATOR once" -- both correct.
**Gas Flags:** None. Single SSTORE operation.
**Verdict:** CORRECT

---

### `data(uint256 i)` [external view]

| Field | Value |
|-------|-------|
| **Signature** | `function data(uint256 i) external view returns (string memory)` |
| **Visibility** | external |
| **Mutability** | view |
| **Parameters** | `i` (uint256): Icon index (0-32) |
| **Returns** | `string memory`: SVG path "d" attribute string |

**State Reads:** `_paths[i]`
**State Writes:** None (view)

**Callers:** DegenerusDeityPass.tokenURI (via IIcons32 interface at ContractAddresses.ICONS_32)
**Callees:** None

**ETH Flow:** None
**Invariants:**
- Reverts with Solidity array out-of-bounds if `i >= 33`
- Returns empty string if path at index `i` was never set (default storage)
- No access control (publicly readable)

**Bounds Checking:** Relies on Solidity's built-in array bounds checking for `string[33]`. If `i >= 33`, the EVM reverts with `Panic(0x32)` (array out-of-bounds). This is safe.

**NatSpec Accuracy:** NatSpec says "Reverts with array out-of-bounds if index >= 33" -- correct. Layout documentation `i = (quadrant * 8) + symbolIndex` matches the icon index scheme (Q0: 0-7, Q1: 8-15, Q2: 16-23, Q3: 24-31, affiliate: 32).
**Gas Flags:** None. Single SLOAD + memory copy.
**Verdict:** CORRECT

---

### `symbol(uint256 quadrant, uint8 idx)` [external view]

| Field | Value |
|-------|-------|
| **Signature** | `function symbol(uint256 quadrant, uint8 idx) external view returns (string memory)` |
| **Visibility** | external |
| **Mutability** | view |
| **Parameters** | `quadrant` (uint256): Quadrant index 0-3; `idx` (uint8): Symbol index within quadrant (0-7) |
| **Returns** | `string memory`: Symbol name, or empty string if quadrant >= 3 |

**State Reads:** `_symQ1[idx]` or `_symQ2[idx]` or `_symQ3[idx]` depending on quadrant
**State Writes:** None (view)

**Callers:** DegenerusDeityPass.tokenURI (via IIcons32 interface)
**Callees:** None

**ETH Flow:** None
**Invariants:**
- For quadrant 0: returns `_symQ1[idx]` (Crypto names)
- For quadrant 1: returns `_symQ2[idx]` (Zodiac names)
- For quadrant 2: returns `_symQ3[idx]` (Cards names)
- For quadrant >= 3: returns empty string "" (Dice names generated dynamically by caller)
- Reverts with array out-of-bounds if `idx >= 8` for quadrants 0-2

**Bounds Checking:**
- `idx` is uint8 (max 255), but Solidity's array bounds check on `string[8]` ensures revert if idx >= 8 for quadrants 0-2
- For quadrant >= 3, returns "" without array access -- no bounds issue

**Consumer Pattern (DegenerusDeityPass):**
```solidity
string memory symbolName = icons.symbol(quadrant, symbolIdx);
if (bytes(symbolName).length == 0) {
    symbolName = string(abi.encodePacked("Dice ", Strings.toString(symbolIdx + 1)));
}
```
This correctly handles the empty-string return for Dice quadrant (3) by generating "Dice 1" through "Dice 8" dynamically.

**NatSpec Accuracy:** NatSpec says "Quadrant 3 (Dice) returns empty string; renderer generates '1..8' dynamically" and "Will revert with array out-of-bounds if idx >= 8 for quadrants 0-2" -- correct. The quadrant naming (0=Crypto, 1=Zodiac, 2=Cards, 3=Dice) matches the 0-indexed getter convention.
**Gas Flags:** None.
**Verdict:** CORRECT
