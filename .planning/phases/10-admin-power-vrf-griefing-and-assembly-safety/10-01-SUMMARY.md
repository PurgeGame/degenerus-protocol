---
phase: 10-admin-power-vrf-griefing-and-assembly-safety
plan: "01"
subsystem: audit
tags: [assembly, storage-layout, evm, solidity, security-audit]

# Dependency graph
requires:
  - phase: 09-gas-analysis
    provides: "gas analysis baselines and audit context"
provides:
  - "ASSY-01 verdict: JackpotModule _raritySymbolBatch assembly PASS with compiler evidence"
  - "ASSY-02 verdict: MintModule _raritySymbolBatch assembly PASS (identical pattern)"
  - "ASSY-03 verdict: _revertDelegate (4 locations) and DegenerusJackpots array-shrink PASS"
  - "traitBurnTicket storage slot 11 confirmed, type address[][256] inplace encoding"
  - "DegenerusGameStorage.sol line 104-105 comment discrepancy resolved: comment is WRONG"
affects:
  - "10-02: ADMIN findings"
  - "10-03: VRF griefing findings"
  - "10-04: Phase 10 synthesis report"
  - "13: final audit report"

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "hardhat storageLayout outputSelection enabled for compiler-authoritative slot verification"
    - "EVM fixed-size array inplace encoding: element i at levelSlot + i (contiguous, no keccak)"
    - "_revertDelegate standard delegatecall bubble-up: revert(add(32, reason), mload(reason))"
    - "array-shrink pattern: mstore(ptr, n) overwrites length word to shrink in-place"

key-files:
  created:
    - ".planning/phases/10-admin-power-vrf-griefing-and-assembly-safety/10-01-SUMMARY.md"
  modified:
    - "hardhat.config.js (added storageLayout outputSelection)"

key-decisions:
  - "ASSY-01 PASS: levelSlot formula keccak256(pad32(lvl) ++ pad32(slot)) is correct Solidity mapping layout; elem = levelSlot + traitId is correct for inplace address[][256] element access"
  - "ASSY-02 PASS: MintModule assembly is byte-for-byte identical to JackpotModule — same verdict applies"
  - "ASSY-03 PASS: _revertDelegate standard pattern safe in all 4 locations; DegenerusJackpots array-shrink safe (n <= 108 allocation)"
  - "Storage comment at DegenerusGameStorage.sol line 104-105 is WRONG: describes nested mapping formula but type is fixed-size array — the assembly is correct, the comment is misleading"

patterns-established:
  - "EVM storage verification: use hardhat storageLayout output as compiler-authoritative arbiter"
  - "Assembly audit methodology: (1) confirm slot via compiler, (2) walk each assembly op against EVM spec, (3) record pass/fail with specific line evidence"

requirements-completed: [ASSY-01, ASSY-02, ASSY-03]

# Metrics
duration: 8min
completed: 2026-03-04
---

# Phase 10 Plan 01: Assembly Safety Audit Summary

**All three assembly findings (ASSY-01/02/03) PASS: traitBurnTicket slot formula verified correct via compiler storageLayout (slot 11, inplace address[][256]); storage comment at line 104-105 identified as WRONG but the assembly itself is correct**

## Performance

- **Duration:** 8 min
- **Started:** 2026-03-04T22:46:04Z
- **Completed:** 2026-03-04T22:54:00Z
- **Tasks:** 2
- **Files modified:** 2

## Accomplishments

- Extracted authoritative compiler storageLayout for `traitBurnTicket` (slot 11, type `mapping(uint24 => address[][256])`, value encoding `inplace`)
- Verified all 5 assembly operations in JackpotModule `_raritySymbolBatch` are correct (ASSY-01 PASS)
- Confirmed MintModule assembly is byte-for-byte identical → ASSY-02 PASS with same rationale
- Verified 4 `_revertDelegate` locations and DegenerusJackpots array-shrink are safe (ASSY-03 PASS)
- Identified and resolved DegenerusGameStorage.sol line 104-105 comment discrepancy (comment wrong, assembly correct)

## Task Commits

Each task was committed atomically:

1. **Task 1: Extract compiler storage layout** - `1fe643b` (chore)
2. **Task 2: Verify ASSY-01/02/03 and write verdicts** - included in plan metadata commit

**Plan metadata:** TBD (docs: complete plan)

## Files Created/Modified

- `hardhat.config.js` - Added `outputSelection: { "*": { "*": ["storageLayout"] } }` to compiler settings
- `.planning/phases/10-admin-power-vrf-griefing-and-assembly-safety/10-01-SUMMARY.md` - This file

---

## ASSY-01: JackpotModule `_raritySymbolBatch` Assembly

**Verdict: PASS**

### Compiler Evidence

```json
{
  "file": "contracts/DegenerusGame.sol",
  "contract": "DegenerusGame",
  "slot": "11",
  "type": "t_mapping(t_uint24,t_array(t_array(t_address)dyn_storage)256_storage)",
  "label": "traitBurnTicket"
}
```

Type expansion:
- Outer: `mapping(uint24 => address[][256])` — `encoding: "mapping"`, `numberOfBytes: "32"`
- Value: `address[][256]` — `encoding: "inplace"`, `numberOfBytes: "8192"` (256 × 32 = contiguous length slots)
- Element: `address[]` — `encoding: "dynamic_array"`, `numberOfBytes: "32"`
- Base: `address` — `encoding: "inplace"`, `numberOfBytes: "20"`

The `encoding: "inplace"` for `address[][256]` is the key: a fixed-size array's elements are stored contiguously starting at the array's base slot. Element `i` is at `baseSlot + i`. This is NOT the nested mapping formula in the comment.

### Check 1: `levelSlot` computation — CORRECT

Assembly:
```solidity
mstore(0x00, lvl)
mstore(0x20, traitBurnTicket.slot)
levelSlot := keccak256(0x00, 0x40)
```

Solidity mapping formula: `keccak256(abi.encode(key, mappingSlot))` = `keccak256(pad32(key) ++ pad32(slot))`.

- `mstore(0x00, lvl)` stores uint24 as a 32-byte left-zero-padded word — this IS `abi.encode(lvl)` (not abi.encodePacked)
- `mstore(0x20, traitBurnTicket.slot)` stores the mapping's slot (11) in the next word
- `keccak256(0x00, 0x40)` hashes 64 bytes — exactly `keccak256(pad32(lvl) ++ pad32(11))`

This matches the Solidity ABI spec for `mapping(uint24 => T)` key lookup. `levelSlot` is the base slot of the `address[][256]` value for key `lvl`. **CORRECT.**

### Check 2: `elem = add(levelSlot, traitId)` — CORRECT

- Compiler confirms `address[][256]` has `encoding: "inplace"` at `levelSlot`
- EVM inplace encoding: element `i` of a fixed-size array at slot `S` is at slot `S + i`
- Therefore `traitBurnTicket[lvl][traitId]` (type `address[]`) has its metadata (length) at slot `levelSlot + traitId`
- `elem = add(levelSlot, traitId)` computes exactly this slot
- `traitId` is `uint8` (0..255) — always within the 256-element array bounds

**CORRECT.** Note: the storage comment at DegenerusGameStorage.sol line 104-105 claiming `keccak256(traitId . keccak256(level . slot))` describes a nested mapping layout and is WRONG for this type. The assembly is correct; the comment is wrong.

### Check 3: `sload(elem)` reads length, `sstore(elem, newLen)` writes length — CORRECT

- For `address[]` (dynamic array), Solidity stores the array length at the array's base slot
- `elem` IS the base slot of `traitBurnTicket[lvl][traitId]`
- `sload(elem)` reads current length; `sstore(elem, newLen)` writes updated length

**CORRECT.** Standard Solidity dynamic array length layout.

### Check 4: Data start `keccak256(0x00, 0x20)` with `elem` at `0x00` — CORRECT

Assembly:
```solidity
mstore(0x00, elem)
let data := keccak256(0x00, 0x20)
```

- Solidity dynamic array data location: `keccak256(lengthSlot)`
- `mstore(0x00, elem)` places the length slot at memory position 0
- `keccak256(0x00, 0x20)` hashes the 32-byte word — exactly `keccak256(elem)`
- `data` = first element's storage slot in `traitBurnTicket[lvl][traitId]`

**CORRECT.** Standard dynamic array data start.

### Check 5: Sequential write `sstore(dst, player); dst = add(dst, 1)` — CORRECT

```solidity
let dst := add(data, len)
for { let k := 0 } lt(k, occurrences) { k := add(k, 1) } {
    sstore(dst, player)
    dst := add(dst, 1)
}
```

- `dst = data + len` starts at the next unwritten element (appending after existing entries)
- Each `address[]` element occupies exactly 1 storage slot (32 bytes)
- Addresses are 20 bytes; Solidity stores them left-padded to 32 bytes; the upper 12 bytes are zero for any valid address
- `sstore(dst, player)` stores the address value (zero-padded) in its slot — matches Solidity layout
- `dst = add(dst, 1)` advances by 1 slot — correct for a non-packed array

Note: Solidity does NOT pack `address[]` elements. Each takes a full 32-byte slot (the `address` type's `encoding: "inplace"` with `numberOfBytes: "20"` means it occupies 20 bytes but address[] elements are NOT packed per array storage rules — each element in a dynamic array is in its own slot).

**CORRECT.** Standard address[] element write.

### ASSY-01 Summary

All 5 checks PASS. The assembly correctly implements bulk writes to `traitBurnTicket[lvl][traitId]` by computing the exact EVM storage slot for a `mapping(uint24 => address[][256])`. No storage corruption risk.

---

## Storage Comment Discrepancy — DegenerusGameStorage.sol Line 104-105

**Resolution: The comment is WRONG; the assembly is correct.**

The comment states:
```
// keccak256(traitId . keccak256(level . slot))   ← nested mapping formula
```

This describes the access pattern for `mapping(uint24 => mapping(uint8 => address[]))` — a nested mapping.

The actual type declaration is:
```solidity
mapping(uint24 => address[][256]) internal traitBurnTicket;
```

The compiler confirms the value type is `address[][256]` with `encoding: "inplace"` (fixed-size array, NOT a mapping). The correct data location formula for element `traitId` is:
- Length slot: `keccak256(abi.encode(lvl, slot)) + traitId`
- Data: `keccak256(keccak256(abi.encode(lvl, slot)) + traitId)`

This is exactly what the assembly computes. The comment misleads readers into thinking a second keccak is applied for the `traitId` dimension when it is actually a simple addition. **The assembly is correct; the comment should be updated to reflect the inplace encoding.**

Severity of comment error: **INFO** — no runtime impact, but creates false impression of the storage layout.

---

## ASSY-02: MintModule `_raritySymbolBatch` Assembly

**Verdict: PASS — identical pattern confirmed**

Source inspection (DegenerusGameMintModule.sol lines 483-518) shows the assembly is byte-for-byte identical in structure to JackpotModule:

```solidity
// levelSlot block (lines 484-488):
assembly ("memory-safe") {
    mstore(0x00, lvl)
    mstore(0x20, traitBurnTicket.slot)
    levelSlot := keccak256(0x00, 0x40)
}

// Per-trait write block (lines 495-514):
assembly ("memory-safe") {
    let elem := add(levelSlot, traitId)
    let len := sload(elem)
    let newLen := add(len, occurrences)
    sstore(elem, newLen)
    mstore(0x00, elem)
    let data := keccak256(0x00, 0x20)
    let dst := add(data, len)
    for { let k := 0 } lt(k, occurrences) { k := add(k, 1) } {
        sstore(dst, player)
        dst := add(dst, 1)
    }
}
```

No structural or semantic differences. All 5 checks from ASSY-01 apply identically. **ASSY-02 PASS.**

---

## ASSY-03: Other Assembly Blocks

### `_revertDelegate` Pattern — 4 Locations

**Verdict: PASS**

Locations:
1. `AdvanceModule.sol:432-434` — `_revertDelegate(bytes memory reason)`
2. `DecimatorModule.sol:82-84` — same pattern
3. `DegeneretteModule.sol:143-145` — same pattern
4. `DegenerusGame.sol:1121-1123` — same pattern

Assembly:
```solidity
assembly ("memory-safe") {
    revert(add(32, reason), mload(reason))
}
```

EVM memory layout for `bytes memory reason`:
- `reason` (the pointer) points to the length word
- `mload(reason)` reads the length word — correct, gives number of data bytes
- `add(32, reason)` = `reason + 32` points to the first data byte (skipping 32-byte length prefix)
- `revert(offset, size)` reverts with `size` bytes starting at `offset`

This is the standard delegatecall revert bubble-up pattern. `reason` was allocated by the ABI decoder; `reason + 32 + reason.length` bytes of memory are always valid. No memory bounds issue.

**PASS** for all 4 locations.

### `DegenerusJackpots.sol` Array-Shrink — Lines 602-605

**Verdict: PASS**

Context:
```solidity
address[] memory tmpW = new address[](108);  // line 233
uint256[] memory tmpA = new uint256[](108);  // line 234
uint256 n;                                    // line 235
// ... n incremented with ++n only on successful _creditOrRefund() calls
winners = tmpW;
amounts = tmpA;
assembly ("memory-safe") {
    mstore(winners, n)
    mstore(amounts, n)
}
```

Analysis:
- `tmpW` and `tmpA` are allocated at max capacity 108
- `n` starts at 0 and is only incremented (with `++n`) when `_creditOrRefund()` returns `true`, which writes to `tmpW[n]`/`tmpA[n]`
- `n` is always <= number of successful `_creditOrRefund()` calls <= 108 (the allocation)
- `mstore(winners, n)` overwrites the length word of `winners` (which is the same pointer as `tmpW` after assignment)
- `mstore(amounts, n)` similarly shrinks `amounts`
- Shrinking a dynamic array's length in-place is safe: no reallocation, no bounds violation, `n <= 108`

No memory corruption. No out-of-bounds write. The Solidity `("memory-safe")` annotation is correct since the writes are to the length word of memory that was originally allocated at 108 and only shrunk.

**PASS.**

---

## Decisions Made

1. **ASSY-01 PASS:** The assembly correctly computes `keccak256(pad32(lvl) || pad32(slot)) + traitId` for the length slot of `traitBurnTicket[lvl][traitId]`. This matches the Solidity inplace encoding for `address[][256]`. The 5-check analysis confirmed no storage corruption risk.

2. **ASSY-02 PASS:** MintModule assembly is byte-for-byte identical to JackpotModule. No independent analysis needed beyond confirming structural identity.

3. **ASSY-03 PASS:** `_revertDelegate` is the standard delegatecall revert pattern; DegenerusJackpots array-shrink is safe with `n <= 108`.

4. **Comment discrepancy is INFO:** The wrong comment at DegenerusGameStorage.sol line 104-105 has no runtime impact. Rated INFO (documentation issue).

## Deviations from Plan

None — plan executed exactly as written. The hardhat.config.js modification to add `outputSelection: storageLayout` was part of the Task 1 execution steps as specified.

## Issues Encountered

None. The storageLayout output was not present in the pre-existing build-info (Hardhat does not include it by default), requiring a config change and `--force` recompile as anticipated in the plan's Task 1 fallback path.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- ASSY-01, ASSY-02, ASSY-03 verdicts available for Phase 10 synthesis report (10-04)
- traitBurnTicket slot 11 and type evidence citable in Phase 13 final report
- Storage comment at DegenerusGameStorage.sol line 104-105 identified as INFO finding; can be fixed or noted in final report
- Phase 10 plans 02 and 03 (ADMIN and VRF griefing) are ready to execute

## Self-Check: PASSED

- FOUND: `.planning/phases/10-admin-power-vrf-griefing-and-assembly-safety/10-01-SUMMARY.md`
- FOUND: commit `1fe643b` (hardhat.config.js storageLayout)
- FOUND: commit `b861b22` (ASSY verdicts SUMMARY.md)

---
*Phase: 10-admin-power-vrf-griefing-and-assembly-safety*
*Completed: 2026-03-04*
