---
phase: 03c-supporting-mechanics-modules
plan: 06
type: execute
wave: 1
depends_on: []
files_modified:
  - .planning/phases/03c-supporting-mechanics-modules/03c-06-FINDINGS-bitpackinglib-integrity.md
autonomous: true
requirements: [MATH-08]

must_haves:
  truths:
    - "Complete mintPacked_ field layout map includes all fields from BitPackingLib AND MintStreakUtils"
    - "No two fields overlap in bit positions"
    - "Every setPacked call site uses the correct mask for its field width"
    - "Every read site uses the correct shift and mask matching its setPacked counterpart"
    - "WHALE_BUNDLE_TYPE mask (2-bit literal 3) is sufficient for all values written (0, 1, 3)"
    - "WhaleModule _nukePassHolderStats hardcoded shift 160 matches MINT_STREAK_LAST_COMPLETED_SHIFT"
    - "setPacked formula (data & ~(mask << shift)) | ((value & mask) << shift) is correct for clear-and-set"
    - "No value written to any field can exceed its mask capacity"
  artifacts:
    - path: ".planning/phases/03c-supporting-mechanics-modules/03c-06-FINDINGS-bitpackinglib-integrity.md"
      provides: "BitPackingLib field packing/unpacking audit findings"
      min_lines: 100
  key_links:
    - from: "contracts/libraries/BitPackingLib.sol (setPacked)"
      to: "All callers (30+ sites)"
      via: "function call with shift/mask/value args"
      pattern: "BitPackingLib\\.setPacked"
    - from: "contracts/modules/DegenerusGameMintStreakUtils.sol (MINT_STREAK_LAST_COMPLETED_SHIFT = 160)"
      to: "contracts/modules/DegenerusGameWhaleModule.sol (line 856, hardcoded 160)"
      via: "magic number duplication"
      pattern: "setPacked.*160"
---

<objective>
Audit BitPackingLib 24-bit field packing/unpacking for correctness across all call sites. Produce a complete field layout map including the undocumented MINT_STREAK_LAST_COMPLETED field, verify no overlaps, and confirm every setPacked/read pair uses matching shift and mask values.

Purpose: MATH-08 requires confirming "BitPackingLib 24-bit field packing/unpacking is correct -- no field overflow or bleed across boundaries." The mintPacked_ uint256 word is read and written by 30+ call sites across 6 different contracts. A single mask/shift mismatch could corrupt adjacent fields. Research identified a documentation gap (MINT_STREAK_LAST_COMPLETED not in BitPackingLib header) and a mask width inconsistency (WHALE_BUNDLE_TYPE comment says 3 bits but mask is 2 bits).
Output: FINDINGS document with complete field map and per-site verification
</objective>

<execution_context>
@/home/zak/.claude/get-shit-done/workflows/execute-plan.md
@/home/zak/.claude/get-shit-done/templates/summary.md
</execution_context>

<context>
@.planning/ROADMAP.md
@.planning/REQUIREMENTS.md
@.planning/phases/03c-supporting-mechanics-modules/3c-RESEARCH.md

Source files (READ-ONLY -- do NOT modify):
@contracts/libraries/BitPackingLib.sol
@contracts/modules/DegenerusGameMintStreakUtils.sol
@contracts/modules/DegenerusGameWhaleModule.sol
@contracts/modules/DegenerusGameBoonModule.sol
@contracts/modules/DegenerusGameMintModule.sol (for setPacked call sites)
@contracts/storage/DegenerusGameStorage.sol (for setPacked call sites)
@contracts/modules/DegenerusGameDegeneretteModule.sol (for read sites)
</context>

<tasks>

<task type="auto">
  <name>Task 1: Build complete field layout map and verify setPacked formula correctness</name>
  <files>.planning/phases/03c-supporting-mechanics-modules/03c-06-FINDINGS-bitpackinglib-integrity.md</files>
  <action>
READ-ONLY AUDIT. Do not modify any contract files.

**Section 1: setPacked Formula Verification**

Read BitPackingLib.setPacked (line 76-83):
```solidity
return (data & ~(mask << shift)) | ((value & mask) << shift);
```

Verify this implements the correct clear-and-set pattern:
1. `mask << shift`: creates the field-width window at the correct position
2. `~(mask << shift)`: inverts to create a "hole" mask
3. `data & ~(mask << shift)`: clears only the target field, preserving all other bits
4. `value & mask`: truncates value to field width (prevents bleed into higher bits)
5. `((value & mask) << shift)`: positions the truncated value at the target field
6. OR combines: cleared data with new field value

This formula is CORRECT for clear-and-set if and only if:
- mask correctly represents the field width
- shift correctly positions the field
- value fits within mask (enforced by `value & mask`)

**Section 2: Complete Field Layout Map**

Build the definitive field layout from ALL source files. Include fields from both BitPackingLib.sol and MintStreakUtils.sol:

| Bit Range | Width | Field Name | Mask | Shift Constant | Defined In |
|-----------|-------|------------|------|----------------|------------|
| [0-23] | 24 | LAST_LEVEL | MASK_24 | LAST_LEVEL_SHIFT (0) | BitPackingLib |
| [24-47] | 24 | LEVEL_COUNT | MASK_24 | LEVEL_COUNT_SHIFT (24) | BitPackingLib |
| [48-71] | 24 | LEVEL_STREAK | MASK_24 | LEVEL_STREAK_SHIFT (48) | BitPackingLib |
| [72-103] | 32 | DAY | MASK_32 | DAY_SHIFT (72) | BitPackingLib |
| [104-127] | 24 | LEVEL_UNITS_LEVEL | MASK_24 | LEVEL_UNITS_LEVEL_SHIFT (104) | BitPackingLib |
| [128-151] | 24 | FROZEN_UNTIL_LEVEL | MASK_24 | FROZEN_UNTIL_LEVEL_SHIFT (128) | BitPackingLib |
| [152-153] | 2 | WHALE_BUNDLE_TYPE | literal 3 | WHALE_BUNDLE_TYPE_SHIFT (152) | BitPackingLib |
| [154-159] | 6 | (unused gap) | - | - | - |
| [160-183] | 24 | MINT_STREAK_LAST_COMPLETED | MASK_24 | MINT_STREAK_LAST_COMPLETED_SHIFT (160) | MintStreakUtils |
| [184-227] | 44 | (unused gap) | - | - | - |
| [228-243] | 16 | LEVEL_UNITS | MASK_16 | LEVEL_UNITS_SHIFT (228) | BitPackingLib |
| [244-255] | 12 | (reserved/unused) | - | - | - |

Verify NO TWO FIELDS OVERLAP by checking that (shift + mask_width) for each field does not intrude into the next field's shift:
- LAST_LEVEL: 0 + 24 = 24. Next: LEVEL_COUNT at 24. OK.
- LEVEL_COUNT: 24 + 24 = 48. Next: LEVEL_STREAK at 48. OK.
- LEVEL_STREAK: 48 + 24 = 72. Next: DAY at 72. OK.
- DAY: 72 + 32 = 104. Next: LEVEL_UNITS_LEVEL at 104. OK.
- LEVEL_UNITS_LEVEL: 104 + 24 = 128. Next: FROZEN_UNTIL_LEVEL at 128. OK.
- FROZEN_UNTIL_LEVEL: 128 + 24 = 152. Next: WHALE_BUNDLE_TYPE at 152. OK.
- WHALE_BUNDLE_TYPE: 152 + 2 = 154. Next used: MINT_STREAK_LAST_COMPLETED at 160. Gap of 6 bits. OK.
- MINT_STREAK_LAST_COMPLETED: 160 + 24 = 184. Next: LEVEL_UNITS at 228. Gap of 44 bits. OK.
- LEVEL_UNITS: 228 + 16 = 244. Remaining: 12 bits unused. OK.

**WHALE_BUNDLE_TYPE inconsistency**: BitPackingLib header comment says "[152-154] WHALE_BUNDLE_TYPE_SHIFT - Bundle type (3 bits)" but the mask is literal `3` (0b11 = 2 bits). The comment claims bits 152-154 (3 bits) but only bits 152-153 are actually used. Bit 154 is in the unused gap. The comment is misleading but functionally harmless IF no code ever writes a value > 3 to this field.

**Section 3: Per-Site setPacked Verification**

For EVERY setPacked call site (enumerate all from grep results), verify:
1. shift matches the intended field
2. mask matches the field width
3. value being written fits within the mask

Enumerate all known setPacked call sites:

**DegenerusGameStorage.sol** (~8 calls):
- Lines 1023, 1029, 1036, 1043: in _activate10LevelPass - writes LEVEL_COUNT, FROZEN_UNTIL_LEVEL, WHALE_BUNDLE_TYPE, LAST_LEVEL
- Lines 1097, 1103, 1109, 1115: in another helper - similar fields

**WhaleModule.sol** (~8 calls):
- Line 249: LEVEL_COUNT_SHIFT, MASK_24, newLevelCount (uint24)
- Line 250: FROZEN_UNTIL_LEVEL_SHIFT, MASK_24, newFrozenLevel (uint24)
- Line 251: WHALE_BUNDLE_TYPE_SHIFT, mask=3, value=3. Value 3 (0b11) fits in 2-bit mask. OK.
- Line 252: LAST_LEVEL_SHIFT, MASK_24, newFrozenLevel (uint24)
- Lines 852-856: _nukePassHolderStats - zeroes LEVEL_COUNT, LEVEL_STREAK, LAST_LEVEL, and hardcoded shift 160 for MINT_STREAK_LAST_COMPLETED

**BoonModule.sol** (~1 call):
- Line 345: LEVEL_COUNT_SHIFT, MASK_24, newLevelCount (uint24, capped at type(uint24).max)

**MintModule.sol** (~10 calls):
- Lines 209-210, 229-230, 249-250, 265-268: writes to LEVEL_UNITS, LEVEL_UNITS_LEVEL, FROZEN_UNTIL_LEVEL, WHALE_BUNDLE_TYPE, LAST_LEVEL, LEVEL_COUNT
- Line 250: WHALE_BUNDLE_TYPE_SHIFT, mask=3, value=0. Clearing. OK.

For each call site, record: file, line, field, shift, mask, value source, max possible value, fits in mask (yes/no).

**Section 4: Per-Site Read Verification**

For every read operation on mintPacked_, verify the shift and mask match the corresponding setPacked:
- Pattern: `uint24((data >> SHIFT) & MASK_24)` or `uint32((data >> SHIFT) & MASK_32)`
- Each read should use the same shift constant and mask as the corresponding write
- Look for any read using a literal shift instead of the constant (like the write at line 856 uses literal 160)

Grep for all mintPacked_ reads across contracts:
- DegenerusGame.sol
- DegenerusGameStorage.sol
- WhaleModule.sol
- BoonModule.sol
- MintModule.sol
- DegeneretteModule.sol (_playerActivityScoreInternal reads LEVEL_COUNT, FROZEN_UNTIL_LEVEL, WHALE_BUNDLE_TYPE)
- MintStreakUtils.sol

For each read, verify shift and mask match the field definition.

**Section 5: Value Overflow Analysis**

For each field, determine the maximum value that code can write:
- LAST_LEVEL: written as level number (uint24). Game has finite levels. Max level realistically < 2^24. OK.
- LEVEL_COUNT: incremented. BoonModule caps at type(uint24).max. WhaleModule adds up to 100 per bundle. Over many bundles, could approach uint24 max (16777215). The cap in BoonModule is correct.
- LEVEL_STREAK: MintStreakUtils caps at type(uint24).max. OK.
- DAY: written as _currentMintDay() or _simulatedDayIndex() cast to uint32. Day index from block.timestamp. Won't overflow uint32 for ~136 years. OK.
- LEVEL_UNITS_LEVEL: written as current level (uint24). Same as LAST_LEVEL. OK.
- FROZEN_UNTIL_LEVEL: ticketStartLevel + 99. Max: ~16M + 99. Fits uint24. OK.
- WHALE_BUNDLE_TYPE: values 0, 1, 3. Max value 3 fits in 2-bit mask. OK.
- MINT_STREAK_LAST_COMPLETED: written as mintLevel (uint24). OK.
- LEVEL_UNITS: uint16, written from ticket count. Max 65535 per level. OK.

**Section 6: Research Findings Confirmation**

Confirm or update the three research pre-findings:
1. Finding 1: WHALE_BUNDLE_TYPE mask vs comment inconsistency (INFORMATIONAL)
2. Finding 2: MINT_STREAK_LAST_COMPLETED not in BitPackingLib layout (INFORMATIONAL)
3. Finding 3: _nukePassHolderStats hardcoded 160 (INFORMATIONAL)

Document all findings with severity ratings.
  </action>
  <verify>
    <automated>test -f .planning/phases/03c-supporting-mechanics-modules/03c-06-FINDINGS-bitpackinglib-integrity.md && grep -c "Section" .planning/phases/03c-supporting-mechanics-modules/03c-06-FINDINGS-bitpackinglib-integrity.md</automated>
  </verify>
  <done>
    - Complete field layout map with all 9 fields and gap analysis
    - No overlaps confirmed with arithmetic proof
    - Every setPacked call site (30+) verified for correct shift/mask/value
    - Every read site verified for matching shift/mask
    - WHALE_BUNDLE_TYPE 2-bit vs 3-bit inconsistency documented
    - MINT_STREAK_LAST_COMPLETED documentation gap documented
    - Hardcoded 160 magic number documented
    - No field overflow possible in any code path
    - FINDINGS document exists with all 6 sections
  </done>
</task>

</tasks>

<verification>
- FINDINGS document contains complete field layout map
- All 30+ setPacked call sites enumerated and verified
- All read sites cross-referenced with write sites
- MATH-08 has a clear PASS/FAIL determination
- No contract files were modified
</verification>

<success_criteria>
- MATH-08 determination: all 24-bit fields pack/unpack correctly with no overlap or bleed
- Complete inventory of all setPacked and read call sites with verification status
- Three research pre-findings confirmed with final severity ratings
- Field layout map is definitive (includes all fields from all source files)
</success_criteria>

<output>
After completion, create `.planning/phases/03c-supporting-mechanics-modules/03c-06-SUMMARY.md`
</output>
