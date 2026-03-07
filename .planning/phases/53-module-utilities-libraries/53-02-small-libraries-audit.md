# Phase 53 Plan 02: Small Libraries Audit

**Libraries:** BitPackingLib.sol (85 lines), EntropyLib.sol (24 lines), GameTimeLib.sol (35 lines), PriceLookupLib.sol (47 lines)
**Auditor:** Claude (automated)
**Date:** 2026-03-07

---

## 1. BitPackingLib.sol

### Overview

Pure utility library for bit-packed storage field operations on 256-bit words. Used extensively across the protocol to manipulate the `mintPacked_` mapping, which encodes per-player mint state into a single `uint256` slot.

### Constants

#### Bit Masks

| Constant | Value | Hex | Description |
|----------|-------|-----|-------------|
| `MASK_16` | `(1 << 16) - 1` = 65535 | `0xFFFF` | 16-bit mask for level units field |
| `MASK_24` | `(1 << 24) - 1` = 16777215 | `0xFFFFFF` | 24-bit mask for level/count/streak fields |
| `MASK_32` | `(1 << 32) - 1` = 4294967295 | `0xFFFFFFFF` | 32-bit mask for day field |

#### Bit Shift Positions

| Constant | Value | Bits Occupied | Width | Mask Used |
|----------|-------|---------------|-------|-----------|
| `LAST_LEVEL_SHIFT` | 0 | [0-23] | 24 | MASK_24 |
| `LEVEL_COUNT_SHIFT` | 24 | [24-47] | 24 | MASK_24 |
| `LEVEL_STREAK_SHIFT` | 48 | [48-71] | 24 | MASK_24 |
| `DAY_SHIFT` | 72 | [72-103] | 32 | MASK_32 |
| `LEVEL_UNITS_LEVEL_SHIFT` | 104 | [104-127] | 24 | MASK_24 |
| `FROZEN_UNTIL_LEVEL_SHIFT` | 128 | [128-151] | 24 | MASK_24 |
| `WHALE_BUNDLE_TYPE_SHIFT` | 152 | [152-154] | 3 | literal `3` |
| `MINT_STREAK_LAST_COMPLETED_SHIFT`* | 160 | [160-183] | 24 | MASK_24 |
| `LEVEL_UNITS_SHIFT` | 228 | [228-243] | 16 | MASK_16 |

*Note: `MINT_STREAK_LAST_COMPLETED_SHIFT` is defined in `DegenerusGameMintStreakUtils` (not in BitPackingLib itself) but operates on the same packed word.

**Gap Analysis:**
- Bits [155-159]: 5-bit gap between WHALE_BUNDLE_TYPE (152-154) and MINT_STREAK_LAST_COMPLETED (160-183). **Intentional** -- unused space.
- Bits [184-227]: 44-bit gap between MINT_STREAK_LAST_COMPLETED (160-183) and LEVEL_UNITS (228-243). **Intentional** -- reserved for future use.
- Bits [244-255]: 12-bit gap after LEVEL_UNITS. **Documented as reserved** in NatSpec.

**Overlap Check:** No fields overlap. All bit ranges are disjoint. VERIFIED CORRECT.

**NatSpec Accuracy:** The header comment states `[152-154]` for WHALE_BUNDLE_TYPE_SHIFT which is correct for 3 bits. However, the header does not mention `MINT_STREAK_LAST_COMPLETED_SHIFT` at bits [160-183] since that constant lives in MintStreakUtils. This is acceptable as MintStreakUtils is a separate contract. All other NatSpec bit ranges are accurate.

### `setPacked(uint256 data, uint256 shift, uint256 mask, uint256 value)` [internal pure]

| Field | Value |
|-------|-------|
| **Signature** | `function setPacked(uint256 data, uint256 shift, uint256 mask, uint256 value) internal pure returns (uint256)` |
| **Visibility** | internal |
| **Mutability** | pure |
| **Parameters** | `data` (uint256): the packed 256-bit word; `shift` (uint256): bit position of target field; `mask` (uint256): bit mask for the field width (unshifted); `value` (uint256): new value to write (will be masked) |
| **Returns** | `uint256`: updated packed word with the target field set to `value` |

**State Reads:** N/A (pure library function)
**State Writes:** N/A (pure library function)

**Callers:**
- `DegenerusGameStorage._processMint()` (6 calls: LEVEL_COUNT, FROZEN_UNTIL_LEVEL, WHALE_BUNDLE_TYPE, LAST_LEVEL, DAY via helper)
- `DegenerusGameStorage._processWhaleBundle()` (5 calls)
- `DegenerusGameMintModule` (8 calls: LEVEL_UNITS, LEVEL_UNITS_LEVEL, FROZEN_UNTIL_LEVEL, WHALE_BUNDLE_TYPE, LAST_LEVEL, LEVEL_COUNT)
- `DegenerusGameWhaleModule` (7 calls: LEVEL_COUNT, FROZEN_UNTIL_LEVEL, WHALE_BUNDLE_TYPE, LAST_LEVEL, DAY, LEVEL_STREAK, MINT_STREAK_LAST_COMPLETED)
- `DegenerusGameBoonModule` (1 call: LEVEL_COUNT)

**Callees:** None

**Invariants:**
1. Only bits at positions `[shift, shift+ceil(log2(mask))]` are modified; all other bits remain unchanged.
2. If `value > mask`, only `value & mask` is stored (truncation by design).
3. The operation is idempotent: `setPacked(setPacked(d,s,m,v), s, m, v) == setPacked(d,s,m,v)`.

**Logic Verification:**
```
(data & ~(mask << shift)) | ((value & mask) << shift)
```
Step 1: `mask << shift` creates a bit mask at the target position.
Step 2: `~(mask << shift)` inverts to create a clearing mask.
Step 3: `data & ~(mask << shift)` clears the target field in data.
Step 4: `(value & mask)` truncates value to field width.
Step 5: `((value & mask) << shift)` positions the value.
Step 6: OR combines the cleared data with the new value.

**Edge Cases:**
- `value > mask`: safely truncated by `value & mask`. CORRECT.
- `shift = 0`: `mask << 0 = mask`, works as expected. CORRECT.
- `shift = 228` (LEVEL_UNITS_SHIFT): `MASK_16 << 228` occupies bits [228-243], within 256-bit range. CORRECT.
- `shift = 248, mask = MASK_24`: would attempt bits [248-271], exceeding 256 bits. However, no caller uses this combination. The library does not guard against it, which is acceptable for an internal pure function (callers control inputs).

**NatSpec Accuracy:** Accurate. Formula in `@dev` matches implementation exactly.
**Gas Flags:** None. Single expression, no redundancy.
**Verdict:** CORRECT

---

## 2. EntropyLib.sol

### Overview

Single-function library providing a deterministic XOR-shift PRNG step. Seeded from Chainlink VRF randomness, used to derive multiple pseudo-random values from a single VRF result.

### `entropyStep(uint256 state)` [internal pure]

| Field | Value |
|-------|-------|
| **Signature** | `function entropyStep(uint256 state) internal pure returns (uint256)` |
| **Visibility** | internal |
| **Mutability** | pure |
| **Parameters** | `state` (uint256): current PRNG state (seeded from VRF) |
| **Returns** | `uint256`: next PRNG state |

**State Reads:** N/A (pure library function)
**State Writes:** N/A (pure library function)

**Callers:**
- `DegenerusGamePayoutUtils` (1 call: level offset randomization)
- `DegenerusGameMintModule` (1 call: lootbox roll entropy)
- `DegenerusGameEndgameModule` (1 call: BAF/decimator entropy)
- `DegenerusGameLootboxModule` (6 calls: level entropy, far entropy, boon generation, deity boon)
- `DegenerusGameJackpotModule` (8 calls: ticket processing, winner selection, BURNIE coin jackpots, LCG step, chunk entropy)

**Callees:** None

**Logic:**
```solidity
unchecked {
    state ^= state << 7;
    state ^= state >> 9;
    state ^= state << 8;
}
```

Three XOR-shift steps operating on a 256-bit integer:
1. Left shift by 7, XOR into state
2. Right shift by 9, XOR into state
3. Left shift by 8, XOR into state

**Unchecked Block Safety:**
- XOR (`^`): Cannot overflow; result is always 256 bits.
- Left shift (`<<`): Bits shifted beyond 255 are discarded (Solidity behavior). No overflow.
- Right shift (`>>`): Fills with zeros. No overflow.
- All three operations produce 256-bit results. The `unchecked` block is safe and saves gas by avoiding unnecessary overflow checks.

**XOR-Shift Analysis:**
- The NatSpec claims "Standard xorshift64 algorithm" but this operates on a 256-bit integer, not 64-bit. This is a **NatSpec discrepancy** -- it should say "xorshift256" or "xorshift adapted for 256 bits."
- Shift constants (7, 9, 8) are commonly used in xorshift variants. For 256-bit state, the distribution quality depends on initial seed quality, which comes from Chainlink VRF (cryptographically secure).
- Since this is deterministic derivation from VRF (not a standalone PRNG for security), the shift constants are adequate. The VRF seed provides the true randomness; entropyStep merely stretches it into multiple derived values.
- **Zero-state risk:** If `state = 0`, all XOR-shift operations produce 0, and `entropyStep(0) = 0`. This is a known property of XOR-shift PRNGs. In practice, VRF always provides a non-zero seed, so this is not exploitable. Callers also commonly XOR with salts (e.g., `entropy ^ rollSalt`), further preventing zero state.

**Invariants:**
1. The function is deterministic: same input always produces same output.
2. Non-zero input always produces non-zero output (XOR-shift property for well-chosen shift triplets).
3. The function is its own inverse: no -- XOR-shift steps are not reversible in general. Each call produces a new derived state.

**NatSpec Accuracy:** Partially accurate. The `@dev` says "Standard xorshift64 algorithm" but operates on uint256. The description "Seeded from VRF, so ultimately secure" is accurate for the use case (deterministic derivation, not standalone randomness). **Minor NatSpec concern: "xorshift64" should be "xorshift" or "xorshift256".**
**Gas Flags:** None. Minimal computation, unchecked is appropriate.
**Verdict:** CORRECT (with NatSpec informational: "xorshift64" label is inaccurate for 256-bit operation)

---

## 3. GameTimeLib.sol

### Overview

Two-function library for computing day indices relative to the contract deployment day. Days reset at 22:57 UTC (JACKPOT_RESET_TIME = 82620 seconds from midnight). Day 1 is the deploy day.

### Constants

| Constant | Type | Value | Description |
|----------|------|-------|-------------|
| `JACKPOT_RESET_TIME` | `uint48` | 82620 | Seconds from midnight UTC for daily reset (22:57:00 UTC = 22*3600 + 57*60 = 82620) |

**Verification:** 22 * 3600 = 79200; 57 * 60 = 3420; 79200 + 3420 = 82620. CORRECT.

### `currentDayIndex()` [internal view]

| Field | Value |
|-------|-------|
| **Signature** | `function currentDayIndex() internal view returns (uint48)` |
| **Visibility** | internal |
| **Mutability** | view |
| **Parameters** | None |
| **Returns** | `uint48`: current day index (1-indexed from deploy day) |

**State Reads:** `block.timestamp` (EVM opcode, not storage)
**State Writes:** N/A

**Callers:**
- `DegenerusGameStorage._currentDay()` (which wraps the call for module access)
- `DegenerusAffiliate` (1 call: affiliate day tracking)

**Callees:** `currentDayIndexAt(uint48)` (delegates computation)

**Logic:** Casts `block.timestamp` to `uint48` and delegates to `currentDayIndexAt`. The uint48 cast is safe: `uint48` can hold values up to 2^48 - 1 = 281,474,976,710,655, which is approximately year 8,919,036. No overflow risk in any practical timeline.

**NatSpec Accuracy:** Accurate. "Day 1 = deploy day" and "Days reset at JACKPOT_RESET_TIME (22:57 UTC)" match behavior.
**Gas Flags:** None.
**Verdict:** CORRECT

### `currentDayIndexAt(uint48 ts)` [internal pure]

| Field | Value |
|-------|-------|
| **Signature** | `function currentDayIndexAt(uint48 ts) internal pure returns (uint48)` |
| **Visibility** | internal |
| **Mutability** | pure |
| **Parameters** | `ts` (uint48): timestamp to evaluate |
| **Returns** | `uint48`: day index (1-indexed from deploy day) |

**State Reads:** N/A (reads compile-time constant `ContractAddresses.DEPLOY_DAY_BOUNDARY`)
**State Writes:** N/A

**Callers:**
- `currentDayIndex()` (within the same library)
- `DegenerusGameStorage._currentDayAt(uint48)` (wraps the call)

**Callees:** None (reads `ContractAddresses.DEPLOY_DAY_BOUNDARY` compile-time constant)

**Logic:**
```solidity
uint48 currentDayBoundary = uint48((ts - JACKPOT_RESET_TIME) / 1 days);
return currentDayBoundary - ContractAddresses.DEPLOY_DAY_BOUNDARY + 1;
```

Step 1: `ts - JACKPOT_RESET_TIME` computes seconds since last daily reset boundary. Since `ts` is uint48 and JACKPOT_RESET_TIME is 82620, this subtracts the daily offset.
Step 2: Division by `1 days` (86400 seconds) gives the "adjusted day number" since epoch.
Step 3: Subtracting `DEPLOY_DAY_BOUNDARY` re-bases to deploy day, `+ 1` makes it 1-indexed.

**Underflow Analysis:**
- `ts - JACKPOT_RESET_TIME`: If `ts < 82620` (before 22:57 UTC on Jan 1, 1970), this would underflow. Since Solidity 0.8.x has overflow/underflow checks and the contract will only be called post-deployment (well past 1970), this is safe. In production, `ts` will be ~1.7 billion+.
- `currentDayBoundary - DEPLOY_DAY_BOUNDARY`: If `DEPLOY_DAY_BOUNDARY > currentDayBoundary`, this would underflow. This can only happen if `ts` is before the deploy timestamp, which is not possible in production (block.timestamp monotonically increases).
- The `+ 1` cannot overflow because day indices are far below uint48 max.

**Day Boundary Example:**
If deploy happens at 2024-01-15 15:00 UTC:
- DEPLOY_DAY_BOUNDARY = (2024-01-15T15:00:00 - 82620) / 86400 = (timestamp - 82620) / 86400
- Day 1 starts at the deploy day's 22:57 UTC boundary
- Day 2 starts at 22:57 UTC the next calendar day

**NatSpec Accuracy:** Accurate. All claims match implementation.
**Gas Flags:** None. Two arithmetic operations, minimal gas.
**Verdict:** CORRECT

---

## 4. PriceLookupLib.sol

### Overview

Single-function library implementing the level-based pricing tier system. Prices follow an introductory tier (levels 0-9) then a repeating 100-level cycle starting at level 10.

### `priceForLevel(uint24 targetLevel)` [internal pure]

| Field | Value |
|-------|-------|
| **Signature** | `function priceForLevel(uint24 targetLevel) internal pure returns (uint256)` |
| **Visibility** | internal |
| **Mutability** | pure |
| **Parameters** | `targetLevel` (uint24): level to query price for |
| **Returns** | `uint256`: price in wei |

**State Reads:** N/A (pure function)
**State Writes:** N/A

**Callers:**
- `DegenerusGamePayoutUtils` (1 call: ticket price lookup, `>> 2` for quarter-ticket)
- `DegenerusGameWhaleModule` (2 calls: lazy pass cost calculation, whale bundle pricing)
- `DegenerusGameEndgameModule` (1 call: BAF target price)
- `DegenerusGameJackpotModule` (4 calls: level prices array, ticket price, BURNIE unit price)
- `DegenerusGameLootboxModule` (2 calls: lootbox target price, deity pass level sum)

**Callees:** None

**Logic (chain of if-else guards):**

```
Intro Tiers (levels 0-9):
  if targetLevel < 5  -> 0.01 ether
  if targetLevel < 10 -> 0.02 ether

First Full Cycle (levels 10-99, no intro tiers):
  if targetLevel < 30  -> 0.04 ether
  if targetLevel < 60  -> 0.08 ether
  if targetLevel < 90  -> 0.12 ether
  if targetLevel < 100 -> 0.16 ether

Repeating Cycle (levels 100+):
  cycleOffset = targetLevel % 100
  if cycleOffset == 0           -> 0.24 ether (milestone)
  if cycleOffset < 30           -> 0.04 ether
  if cycleOffset < 60           -> 0.08 ether
  if cycleOffset < 90           -> 0.12 ether
  else (cycleOffset 90-99)      -> 0.16 ether
```

**Price Tier Verification:**

| Level Range | Price (ETH) | Price (wei) | Plan Spec Match |
|-------------|-------------|-------------|-----------------|
| 0-4 | 0.01 | 10000000000000000 | MATCH |
| 5-9 | 0.02 | 20000000000000000 | MATCH |
| 10-29 | 0.04 | 40000000000000000 | MATCH |
| 30-59 | 0.08 | 80000000000000000 | MATCH |
| 60-89 | 0.12 | 120000000000000000 | MATCH |
| 90-99 | 0.16 | 160000000000000000 | MATCH |
| x00 (100,200,...) | 0.24 | 240000000000000000 | MATCH |
| x01-x29 | 0.04 | 40000000000000000 | MATCH |
| x30-x59 | 0.08 | 80000000000000000 | MATCH |
| x60-x89 | 0.12 | 120000000000000000 | MATCH |
| x90-x99 | 0.16 | 160000000000000000 | MATCH |

**Boundary Condition Verification:**

| Level | Expected | Code Path | Result |
|-------|----------|-----------|--------|
| 0 | 0.01 ETH | `< 5` true | CORRECT |
| 4 | 0.01 ETH | `< 5` true | CORRECT |
| 5 | 0.02 ETH | `< 5` false, `< 10` true | CORRECT |
| 9 | 0.02 ETH | `< 10` true | CORRECT |
| 10 | 0.04 ETH | `< 30` true | CORRECT |
| 29 | 0.04 ETH | `< 30` true | CORRECT |
| 30 | 0.08 ETH | `< 30` false, `< 60` true | CORRECT |
| 59 | 0.08 ETH | `< 60` true | CORRECT |
| 60 | 0.12 ETH | `< 60` false, `< 90` true | CORRECT |
| 89 | 0.12 ETH | `< 90` true | CORRECT |
| 90 | 0.16 ETH | `< 90` false, `< 100` true | CORRECT |
| 99 | 0.16 ETH | `< 100` true | CORRECT |
| 100 | 0.24 ETH | `% 100 = 0` | CORRECT |
| 101 | 0.04 ETH | `% 100 = 1, < 30` true | CORRECT |
| 129 | 0.04 ETH | `% 100 = 29, < 30` true | CORRECT |
| 130 | 0.08 ETH | `% 100 = 30, < 60` true | CORRECT |
| 200 | 0.24 ETH | `% 100 = 0` | CORRECT |
| 299 | 0.16 ETH | `% 100 = 99, else` | CORRECT |

**NatSpec Analysis:**
The NatSpec states levels 10+ use a "100-level cycle, excluding intro tiers." This is accurate. The comment describes the cycle tiers correctly. However, note that the NatSpec says levels "x01-x29" for the first cycle tier, but for levels 10-29, the code uses `targetLevel < 30` (not modular arithmetic). This is functionally equivalent since levels 10-29 and x01-x29 produce the same price. The NatSpec is slightly misleading here because levels 10-29 don't use cycleOffset -- they hit the direct comparison path. But the resulting prices are identical.

**Gas Flags:** The function uses early returns (if-else chain), which is gas-optimal for the most common case (lower levels are more frequently queried). No redundant computation.

**Invariants:**
1. Every possible uint24 input produces a valid non-zero price.
2. Prices are monotonically non-decreasing within a cycle (0.04 -> 0.08 -> 0.12 -> 0.16), with milestone levels (x00) being the highest at 0.24.
3. The function is deterministic and pure.

**Verdict:** CORRECT

---

## BitPackingLib Bit Layout Diagram

Visual layout of the 256-bit `mintPacked_[player]` word:

```
Bit 255                                                                    Bit 0
|                                                                              |
v                                                                              v
[reserved ][LEVEL_UNITS][--------gap--------][STREAK_LAST][--gap--][WHALE][FROZEN_UNTIL ][UNITS_LEVEL  ][    DAY     ][  STREAK   ][ LVL_COUNT ][LAST_LEVEL  ]
[244-255  ][228-243    ][184-227            ][160-183    ][155-159][152-4][128-151      ][104-127      ][72-103      ][48-71      ][24-47      ][0-23        ]
  12 bits    16 bits      44 bits (unused)    24 bits     5 bits  3 bits  24 bits        24 bits        32 bits       24 bits      24 bits      24 bits
```

**Field Summary:**

| Position | Width | Field | Purpose |
|----------|-------|-------|---------|
| [0-23] | 24 | LAST_LEVEL | Last level the player purchased |
| [24-47] | 24 | LEVEL_COUNT | Total number of level purchases |
| [48-71] | 24 | LEVEL_STREAK | Consecutive level streak count |
| [72-103] | 32 | DAY | Day index of last purchase (enough for 11.7M years) |
| [104-127] | 24 | LEVEL_UNITS_LEVEL | Which level the units count tracks |
| [128-151] | 24 | FROZEN_UNTIL_LEVEL | Whale bundle frozen level target |
| [152-154] | 3 | WHALE_BUNDLE_TYPE | Bundle type: 0=none, 1=10-lvl, 3=100-lvl |
| [155-159] | 5 | (gap) | Unused, available for future fields |
| [160-183] | 24 | MINT_STREAK_LAST_COMPLETED | Last level credited for mint streak (defined in MintStreakUtils) |
| [184-227] | 44 | (gap) | Unused, available for future fields |
| [228-243] | 16 | LEVEL_UNITS | Units purchased at current level (max 65535) |
| [244-255] | 12 | (reserved) | Documented as reserved in NatSpec |

**Total used:** 199 bits of 256 (78%). **Remaining:** 61 bits across 3 gaps.

---

## PriceLookupLib Price Tier Table

Complete price tier reference with cycle visualization:

```
Level:  0    4  5    9  10        29  30        59  60        89  90   99  100  101       129  130       200
Price: 0.01 ETH |0.02 ETH| 0.04 ETH   | 0.08 ETH   | 0.12 ETH   |0.16 ETH|0.24|  0.04 ETH  |  0.08... |0.24
       ----intro----      |-------------- first cycle (no intro) --------| |--- repeating 100-lvl cycle -->
```

| Tier | Levels | Price (ETH) | Price (wei) | Frequency |
|------|--------|-------------|-------------|-----------|
| Intro Low | 0-4 | 0.01 | 1e16 | Once (5 levels) |
| Intro High | 5-9 | 0.02 | 2e16 | Once (5 levels) |
| Cycle Low | 10-29, x01-x29 | 0.04 | 4e16 | 20 levels per cycle |
| Cycle Mid | 30-59, x30-x59 | 0.08 | 8e16 | 30 levels per cycle |
| Cycle High | 60-89, x60-x89 | 0.12 | 1.2e17 | 30 levels per cycle |
| Cycle Final | 90-99, x90-x99 | 0.16 | 1.6e17 | 10 levels per cycle |
| Milestone | 100, 200, 300... | 0.24 | 2.4e17 | 1 level per cycle |

**Cost per full 100-level cycle (levels 100-199):**
- 1 milestone: 0.24 ETH
- 29 low: 29 * 0.04 = 1.16 ETH
- 30 mid: 30 * 0.08 = 2.40 ETH
- 30 high: 30 * 0.12 = 3.60 ETH
- 10 final: 10 * 0.16 = 1.60 ETH
- **Total per cycle: 9.00 ETH** (at 1 ticket per level)

---

## Library Call Sites

### BitPackingLib Call Sites

| Contract | Import | Usage Pattern | Fields Accessed |
|----------|--------|---------------|-----------------|
| **DegenerusGame** | Yes | Read-only (shift + mask extraction) | FROZEN_UNTIL_LEVEL, LAST_LEVEL, LEVEL_COUNT, WHALE_BUNDLE_TYPE |
| **DegenerusGameStorage** | Yes | Read + write (setPacked calls) | FROZEN_UNTIL_LEVEL, LAST_LEVEL, LEVEL_COUNT, WHALE_BUNDLE_TYPE, DAY |
| **DegenerusGameMintModule** | Yes | Read + write (setPacked calls) | LAST_LEVEL, LEVEL_COUNT, LEVEL_UNITS, LEVEL_UNITS_LEVEL, FROZEN_UNTIL_LEVEL, WHALE_BUNDLE_TYPE |
| **DegenerusGameWhaleModule** | Yes | Read + write (setPacked + direct bit ops) | FROZEN_UNTIL_LEVEL, LEVEL_COUNT, WHALE_BUNDLE_TYPE, LAST_LEVEL, DAY, LEVEL_STREAK, MINT_STREAK_LAST_COMPLETED |
| **DegenerusGameAdvanceModule** | Yes | Read-only (shift + mask extraction) | DAY, FROZEN_UNTIL_LEVEL |
| **DegenerusGameBoonModule** | Yes | Read + write (setPacked calls) | LEVEL_COUNT |
| **DegenerusGameMintStreakUtils** | Yes | Read + write (direct bit ops + mask) | LEVEL_STREAK, MINT_STREAK_LAST_COMPLETED |
| **DegenerusGameDegeneretteModule** | Yes | Read-only (shift + mask extraction) | LEVEL_COUNT, FROZEN_UNTIL_LEVEL, WHALE_BUNDLE_TYPE |

**Total importing contracts: 8** (DegenerusGame, DegenerusGameStorage, MintModule, WhaleModule, AdvanceModule, BoonModule, MintStreakUtils, DegeneretteModule)

Note: DecimatorModule and LootboxModule do NOT import BitPackingLib (contrary to the plan's hypothesis).

### EntropyLib Call Sites

| Contract | Import | Call Count | Usage |
|----------|--------|------------|-------|
| **DegenerusGamePayoutUtils** | Yes | 1 | Level offset randomization for payout distribution |
| **DegenerusGameMintModule** | Yes | 1 | Lootbox roll entropy derivation |
| **DegenerusGameEndgameModule** | Yes | 1 | BAF/decimator entropy derivation |
| **DegenerusGameLootboxModule** | Yes | 6 | Level entropy, far entropy, boon generation, deity boon rolls |
| **DegenerusGameJackpotModule** | Yes | 8 | Ticket processing, winner selection, BURNIE coin jackpots, LCG step, chunk entropy |

**Total importing contracts: 5** (PayoutUtils, MintModule, EndgameModule, LootboxModule, JackpotModule)

Note: DecimatorModule and DegeneretteModule do NOT import EntropyLib (contrary to the plan's hypothesis). They receive entropy-derived values from callers rather than calling EntropyLib directly.

### GameTimeLib Call Sites

| Contract | Import | Call Count | Usage |
|----------|--------|------------|-------|
| **DegenerusGameStorage** | Yes | 2 | `_currentDay()` wraps `currentDayIndex()`; `_currentDayAt()` wraps `currentDayIndexAt()` |
| **DegenerusAffiliate** | Yes | 1 | Affiliate day tracking for commission calculations |

**Total importing contracts: 2** (DegenerusGameStorage, DegenerusAffiliate)

All module access to day index goes through DegenerusGameStorage helper functions, not direct GameTimeLib calls.

### PriceLookupLib Call Sites

| Contract | Import | Call Count | Usage |
|----------|--------|------------|-------|
| **DegenerusGamePayoutUtils** | Yes | 1 | Ticket price lookup (`>> 2` for quarter-ticket unit price) |
| **DegenerusGameWhaleModule** | Yes | 2 | Lazy pass cost (sum-of-level-prices), whale bundle level pricing |
| **DegenerusGameEndgameModule** | Yes | 1 | BAF target price for endgame calculations |
| **DegenerusGameJackpotModule** | Yes | 4 | Level prices array, ticket price, BURNIE coin unit price |
| **DegenerusGameLootboxModule** | Yes | 2 | Lootbox target price, deity pass level-sum pricing |

**Total importing contracts: 5** (PayoutUtils, WhaleModule, EndgameModule, JackpotModule, LootboxModule)

Note: MintModule does NOT import PriceLookupLib directly; it receives price information from the game contract. This is by design -- MintModule's pricing comes from DegenerusGame which calls into MintModule via delegatecall, passing the price via parameters.

---

## Findings Summary

### Verdict Summary

| Library | Functions | Constants | Verdicts |
|---------|-----------|-----------|----------|
| BitPackingLib | 1 | 10 (3 masks + 7 shifts) | 1 CORRECT |
| EntropyLib | 1 | 0 | 1 CORRECT (NatSpec informational) |
| GameTimeLib | 2 | 1 | 2 CORRECT |
| PriceLookupLib | 1 | 0 | 1 CORRECT |
| **Total** | **5** | **11** | **5 CORRECT, 0 CONCERN, 0 BUG** |

### Issues Found

**BUG:** None

**CONCERN:** None

**GAS:** None

**INFORMATIONAL:**
1. **EntropyLib NatSpec:** `@dev` says "Standard xorshift64 algorithm" but operates on uint256. Should say "xorshift" or "xorshift adapted for 256 bits." Zero impact on correctness or security.
2. **BitPackingLib NatSpec:** Header comment does not document bits [160-183] (MINT_STREAK_LAST_COMPLETED). Acceptable because that constant is defined in MintStreakUtils, not BitPackingLib.
3. **PriceLookupLib NatSpec:** Describes levels 10-29 as part of "100-level cycle" but code uses direct comparison (not modular arithmetic) for levels < 100. Functionally equivalent but slightly misleading.

### Cross-Library Dependencies

```
BitPackingLib  <-- no dependencies (standalone)
EntropyLib     <-- no dependencies (standalone)
GameTimeLib    <-- ContractAddresses (compile-time constant)
PriceLookupLib <-- no dependencies (standalone)
```

All four libraries are leaf dependencies with no circular references. Three are fully standalone; GameTimeLib depends on a compile-time constant.

### Security Assessment

All four libraries are **pure/view internal functions** with no access control requirements, no ETH handling, and no external calls. They pose no direct attack surface. Their security properties are:
1. **BitPackingLib:** Correct bit manipulation. No value truncation bugs. Callers responsible for passing valid shift/mask combinations.
2. **EntropyLib:** Deterministic derivation from VRF. Not used as standalone randomness. Zero-state produces zero output, but VRF seeds are always non-zero.
3. **GameTimeLib:** Arithmetic safe post-deployment. Underflow impossible in production.
4. **PriceLookupLib:** Complete coverage of all uint24 inputs. No missing branches. All prices non-zero.
