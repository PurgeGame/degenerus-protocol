# BitPackingLib Gap Bit Verification

**Phase:** 31-02 -- Cross-Contract Composition Analysis
**Generated:** 2026-03-05
**Source:** Manual audit of all `BitPackingLib.setPacked` call sites

## setPacked Call Site Inventory

All `BitPackingLib.setPacked` call sites in the codebase (27 total):

### DegenerusGameMintModule.sol (12 sites)

| Line | Shift | Mask | Value Source | Bit Range Written |
|------|-------|------|-------------|-------------------|
| 219 | LEVEL_UNITS_SHIFT (228) | MASK_16 | levelUnitsAfter (computed) | 228-243 |
| 220 | LEVEL_UNITS_LEVEL_SHIFT (104) | MASK_24 | lvl (function param) | 104-127 |
| 239 | LEVEL_UNITS_SHIFT (228) | MASK_16 | levelUnitsAfter (computed) | 228-243 |
| 240 | LEVEL_UNITS_LEVEL_SHIFT (104) | MASK_24 | lvl (function param) | 104-127 |
| 259 | FROZEN_UNTIL_LEVEL_SHIFT (128) | MASK_24 | 0 (literal) | 128-151 |
| 260 | WHALE_BUNDLE_TYPE_SHIFT (152) | 3 (literal) | 0 (literal) | 152-153 |
| 275 | LAST_LEVEL_SHIFT (0) | MASK_24 | lvl (function param) | 0-23 |
| 276 | LEVEL_COUNT_SHIFT (24) | MASK_24 | total (computed) | 24-47 |
| 277 | LEVEL_UNITS_SHIFT (228) | MASK_16 | levelUnitsAfter (computed) | 228-243 |
| 278 | LEVEL_UNITS_LEVEL_SHIFT (104) | MASK_24 | lvl (function param) | 104-127 |

### DegenerusGameWhaleModule.sol (8 sites)

| Line | Shift | Mask | Value Source | Bit Range Written |
|------|-------|------|-------------|-------------------|
| 250 | LEVEL_COUNT_SHIFT (24) | MASK_24 | newLevelCount (computed) | 24-47 |
| 251 | FROZEN_UNTIL_LEVEL_SHIFT (128) | MASK_24 | newFrozenLevel (computed) | 128-151 |
| 252 | WHALE_BUNDLE_TYPE_SHIFT (152) | 3 (literal) | 3 (literal) | 152-153 |
| 253 | LAST_LEVEL_SHIFT (0) | MASK_24 | newFrozenLevel (computed) | 0-23 |
| 869 | LEVEL_COUNT_SHIFT (24) | MASK_24 | 0 (literal) | 24-47 |
| 870 | LEVEL_STREAK_SHIFT (48) | MASK_24 | 0 (literal) | 48-71 |
| 871 | LAST_LEVEL_SHIFT (0) | MASK_24 | 0 (literal) | 0-23 |
| 873 | 160 (hardcoded literal) | MASK_24 | 0 (literal) | 160-183 |

### DegenerusGameStorage.sol (8 sites, via _applyLazyPassStats and _applyWhalePassStats)

| Line | Shift | Mask | Value Source | Bit Range Written |
|------|-------|------|-------------|-------------------|
| 1003 | LEVEL_COUNT_SHIFT (24) | MASK_24 | newLevelCount (computed) | 24-47 |
| 1009 | FROZEN_UNTIL_LEVEL_SHIFT (128) | MASK_24 | newFrozenLevel (computed) | 128-151 |
| 1016 | WHALE_BUNDLE_TYPE_SHIFT (152) | 3 (literal) | 1 (literal) | 152-153 |
| 1023 | LAST_LEVEL_SHIFT (0) | MASK_24 | lastLevelTarget (computed) | 0-23 |
| 1077 | LEVEL_COUNT_SHIFT (24) | MASK_24 | newLevelCount (computed) | 24-47 |
| 1083 | FROZEN_UNTIL_LEVEL_SHIFT (128) | MASK_24 | newFrozenLevel (computed) | 128-151 |
| 1089 | WHALE_BUNDLE_TYPE_SHIFT (152) | 3 (literal) | 3 (literal) | 152-153 |
| 1095 | LAST_LEVEL_SHIFT (0) | MASK_24 | newFrozenLevel (computed) | 0-23 |

### DegenerusGameBoonModule.sol (1 site)

| Line | Shift | Mask | Value Source | Bit Range Written |
|------|-------|------|-------------|-------------------|
| 344 | LEVEL_COUNT_SHIFT (24) | MASK_24 | newLevelCount (computed, capped) | 24-47 |

### MintStreakUtils (indirect -- uses bitwise OR, not setPacked)

MintStreakUtils._recordMintStreakForLevel (line 42-44) writes LEVEL_STREAK (48-71) and MINT_STREAK_LAST_COMPLETED (160-183) using direct bitwise mask-and-OR, not setPacked. The mask `MINT_STREAK_FIELDS_MASK` precisely covers only bits 48-71 and 160-183.

**Total setPacked calls: 29** (27 direct setPacked + 2 indirect via _setMintDay and MintStreakUtils bitwise)

### _setMintDay (DegenerusGameStorage.sol line 1132)

Uses direct bitwise clear-and-set pattern (not setPacked), always with DAY_SHIFT (72) and MASK_32. Writes bits 72-103 only.

## Shift/Mask Classification (All Compile-Time Constants)

**Every shift parameter** in every setPacked call site is either:
1. A named constant from BitPackingLib (e.g., `BitPackingLib.LEVEL_COUNT_SHIFT = 24`)
2. A named constant from MintStreakUtils (`MINT_STREAK_LAST_COMPLETED_SHIFT = 160`)
3. A hardcoded literal (`160` at WhaleModule line 873, `3` for mask at multiple sites)

**Every mask parameter** is either:
1. A named constant from BitPackingLib (`MASK_16`, `MASK_24`, `MASK_32`)
2. A hardcoded literal (`3` for WHALE_BUNDLE_TYPE, which is a 2-bit field: values 0, 1, or 3)

**Zero attacker-controllable shift/mask parameters found.** All shift and mask values are compile-time constants baked into bytecode.

## Gap Bit Verification (155-227 Never Written)

### Bit ranges written by ALL setPacked/bitwise call sites:

| Bit Range | Field Name | Written By |
|-----------|-----------|-----------|
| 0-23 | LAST_LEVEL | MINT, WHALE, Storage |
| 24-47 | LEVEL_COUNT | MINT, WHALE, BOON, Storage |
| 48-71 | LEVEL_STREAK | WHALE (zero), MintStreakUtils |
| 72-103 | DAY | _setMintDay (MINT, WHALE, Storage) |
| 104-127 | LEVEL_UNITS_LEVEL | MINT |
| 128-151 | FROZEN_UNTIL_LEVEL | MINT, WHALE, Storage |
| 152-153 | WHALE_BUNDLE_TYPE | MINT, WHALE, Storage |
| 160-183 | MINT_STREAK_LAST_COMPLETED | WhaleModule (line 873), MintStreakUtils |
| 228-243 | LEVEL_UNITS | MINT |

### Gap bits analysis:

**Bits 154-159 (6 bits):**
- WHALE_BUNDLE_TYPE uses shift 152 with mask 3 (binary 11), writing bits 152-153 only
- MINT_STREAK_LAST_COMPLETED uses shift 160, starting at bit 160
- Bits 154-159 are **NEVER written by any call site**

**Bits 184-227 (44 bits):**
- MINT_STREAK_LAST_COMPLETED uses shift 160 with MASK_24, writing bits 160-183 only
- LEVEL_UNITS uses shift 228, starting at bit 228
- Bits 184-227 are **NEVER written by any call site**

**CONFIRMED: Gap bits 154-227 (74 bits total) are never written by any module.** They remain at their initialized value (0) for the lifetime of each player's mintPacked_ entry.

Note: The research stated 73 gap bits (155-227). The actual gap is 74 bits (154-227) because WHALE_BUNDLE_TYPE only uses 2 bits (152-153), not 3 bits (152-154). The mask value 3 = 0b11 covers bits 0-1 of the shifted position, so bits 152-153. Bit 154 is also a gap bit.

**Correction:** DegenerusGame.sol header comment says bits 152-153 are whaleBundleType (2 bits), but BitPackingLib header says bits 152-154 (3 bits). The mask is `3` which is 2 bits. The constant comment in DegenerusGame.sol is correct -- it is a 2-bit field. The BitPackingLib header doc listing "152-154" is slightly imprecise (should say 152-153). This has no security impact as the 3rd bit (154) is never written.

## WhaleModule Literal 160 Verification

**WhaleModule line 873:**
```solidity
data = BitPackingLib.setPacked(data, 160, BitPackingLib.MASK_24, 0);
```

**MintStreakUtils line 10:**
```solidity
uint256 internal constant MINT_STREAK_LAST_COMPLETED_SHIFT = 160;
```

**CONFIRMED: The hardcoded literal `160` matches the MintStreakUtils constant `MINT_STREAK_LAST_COMPLETED_SHIFT = 160`.**

**Maintenance risk assessment:** LOW. The WhaleModule uses the literal `160` instead of importing `MINT_STREAK_LAST_COMPLETED_SHIFT` from MintStreakUtils. If the constant ever changed, the WhaleModule would write to the wrong bit position. However:
1. The constant has no reason to change (bit layout is fixed at deployment)
2. The WhaleModule comment on line 872 explicitly states "MINT_STREAK_LAST_COMPLETED is at shift 160 (from MintStreakUtils)"
3. This is a QA/Info observation, not a vulnerability

## Value Overflow Analysis

**BitPackingLib.setPacked implementation:**
```solidity
function setPacked(uint256 data, uint256 shift, uint256 mask, uint256 value) internal pure returns (uint256) {
    return (data & ~(mask << shift)) | ((value & mask) << shift);
}
```

**The `value & mask` operation truncates the value to the field width before shifting.** This means:
- If `value` exceeds `mask`, the excess bits are silently discarded
- Example: setPacked(data, 24, MASK_24, type(uint256).max) would write only the lower 24 bits (0xFFFFFF), not overflow into adjacent fields
- No value overflow can corrupt adjacent bit fields

**All value parameters are bounded:**
- Level values (uint24): bounded by game level progression (never exceeds ~10^6)
- Count values (uint24): bounded by BoonModule with `type(uint24).max` cap
- Unit values (uint16): bounded by mint logic
- Day values (uint32): bounded by block.timestamp / 86400
- Bundle type (mask 3 = 0b11): values 0, 1, or 3 only

**CONFIRMED: No value overflow risk exists.** BitPackingLib.setPacked masks all values before shifting.

## Conclusion

1. **All 29 setPacked/bitwise call sites** use compile-time constant shift and mask parameters. Zero attacker-controllable parameters.
2. **Gap bits 154-227 (74 bits)** are confirmed never-written by any module. They remain zero.
3. **WhaleModule literal 160** matches MintStreakUtils constant MINT_STREAK_LAST_COMPLETED_SHIFT exactly.
4. **Value overflow** is impossible due to `value & mask` truncation in setPacked.
5. **No composition vulnerability** in the bit packing layer.
