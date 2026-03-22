# Phase 73: Boon Storage Packing - Research

**Researched:** 2026-03-22
**Domain:** Solidity storage packing, EVM gas optimization, bit manipulation
**Confidence:** HIGH

## Summary

The DegenerusGame contract currently stores per-player boon state across 32 separate `mapping(address => ...)` declarations, each occupying its own storage slot per player. This means a single call to `checkAndClearExpiredBoon` performs up to 29 cold SLOADs (2,100 gas each = ~60,900 gas worst-case) plus potentially 29 cold SSTOREs for cleanup. The requirement is to pack all this per-player boon state into a 2-slot struct that can be loaded with 2 SLOADs and written back with at most 2 SSTOREs per operation.

The boon system spans 4 contracts via delegatecall: `DegenerusGameBoonModule` (consumption/cleanup), `DegenerusGameLootboxModule` (_applyBoon, _activeBoonCategory, _rollLootboxBoons), `DegenerusGameWhaleModule` (lootbox boost consumption during purchases, whale/lazy pass boon consumption), and `DegenerusGameMintModule` (purchase boost consumption). All operate on shared storage through the delegatecall pattern, so the packed struct definition goes in `DegenerusGameStorage.sol` and all modules get it automatically.

**Primary recommendation:** Define a 2-slot `BoonPacked` struct in `DegenerusGameStorage.sol` using uint24 day fields (max 16,777,215 days = 45,960+ years) and uint8 tier/bps-encoded fields. Replace all 32 boon mappings with a single `mapping(address => BoonPacked)`. Rewrite all boon functions to use read-modify-write on the struct. The lootbox boost tier simplification (BOON-05) replaces 3 bool + 3 day + 3 deityDay = 9 mappings with a single uint8 tier field (0=none, 1=5%, 2=15%, 3=25%).

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| BOON-01 | All 29 per-player boon mappings replaced with a 2-slot packed struct using uint24 day fields and uint8 lootboxTier | Struct layout designed below (256 + 208 bits = 2 slots), replaces all 32 boon mappings |
| BOON-02 | checkAndClearExpiredBoon operates on packed struct with 2 SLOADs instead of 29 separate cold SLOADs | Read-modify-write pattern documented; function loads slot0+slot1 once, clears expired fields in memory, writes back |
| BOON-03 | _applyBoon and all boon consumption functions use read-modify-write on packed struct | Pattern documented for each boon category; _applyBoon branches on boonType and modifies specific fields |
| BOON-04 | All boon consumption functions (consumeCoinflipBoon, consumePurchaseBoost, consumeDecimatorBoost, consumeActivityBoon) updated for packed layout | Each function loads struct, reads relevant fields, clears them, writes back; documented per-function |
| BOON-05 | Lootbox boost tier logic uses single uint8 tier field instead of 3 separate bool+day+deityDay mapping sets | Tier encoding (0=none, 1=5%, 2=15%, 3=25%) replaces lootboxBoon5Active/15/25 + their day + deityDay = 9 mappings -> 2 fields |
| BOON-06 | All existing tests pass after storage layout change with equivalent behavior | Test infrastructure documented; Hardhat + Foundry dual stack; WhaleBundle.test.js has specific boon tests |
</phase_requirements>

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| Solidity | 0.8.34 | Smart contract language | Project-locked compiler version |
| Foundry | latest | Fuzz testing + forge inspect for slot verification | Already in project |
| Hardhat | latest | Unit/integration/edge tests | Already in project |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| BitPackingLib | internal | Generic setPacked helper for 256-bit words | Already exists at contracts/libraries/BitPackingLib.sol |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Manual bit ops | Solidity struct packing (compiler auto-packs) | Compiler auto-packing works for structs with sub-32-byte members; however manual assembly would save gas on reads for via_ir + optimizer_runs=2 -- but project already uses Solidity struct packing for AutoRebuyState successfully |
| BoonPackingLib | Inline bit operations | A dedicated lib adds clarity but costs extra JUMP; inline is fine given the project uses BitPackingLib sparingly |

## Architecture Patterns

### Current Storage Layout (32 boon mappings, 32 slots per player)

Slot positions from `forge inspect`:

**Group 1: Core boon values (slots 25-41)**
| Slot | Variable | Type | Bytes Used |
|------|----------|------|------------|
| 25 | coinflipBoonDay | uint48 | 6 |
| 26 | lootboxBoon5Active | bool | 1 |
| 27 | lootboxBoon5Day | uint48 | 6 |
| 28 | lootboxBoon15Active | bool | 1 |
| 29 | lootboxBoon15Day | uint48 | 6 |
| 30 | lootboxBoon25Active | bool | 1 |
| 31 | lootboxBoon25Day | uint48 | 6 |
| 32 | whaleBoonDay | uint48 | 6 |
| 33 | whaleBoonDiscountBps | uint16 | 2 |
| 34 | activityBoonPending | uint24 | 3 |
| 35 | activityBoonDay | uint48 | 6 |
| 38 | purchaseBoostBps | uint16 | 2 |
| 39 | purchaseBoostDay | uint48 | 6 |
| 40 | decimatorBoostBps | uint16 | 2 |
| 41 | coinflipBoonBps | uint16 | 2 |

**Group 2: Deity-source day tracking (slots 72-82)**
| Slot | Variable | Type | Bytes Used |
|------|----------|------|------------|
| 72 | deityBoonDay | uint48 | 6 |
| 73 | deityBoonUsedMask | uint8 | 1 |
| 74 | deityBoonRecipientDay | uint48 | 6 |
| 75 | deityCoinflipBoonDay | uint48 | 6 |
| 76 | deityLootboxBoon5Day | uint48 | 6 |
| 77 | deityLootboxBoon15Day | uint48 | 6 |
| 78 | deityLootboxBoon25Day | uint48 | 6 |
| 79 | deityPurchaseBoostDay | uint48 | 6 |
| 80 | deityDecimatorBoostDay | uint48 | 6 |
| 81 | deityWhaleBoonDay | uint48 | 6 |
| 82 | deityActivityBoonDay | uint48 | 6 |

**Group 3: Deity pass boon (slots 85-87)**
| Slot | Variable | Type | Bytes Used |
|------|----------|------|------------|
| 85 | deityPassBoonTier | uint8 | 1 |
| 86 | deityPassBoonDay | uint48 | 6 |
| 87 | deityDeityPassBoonDay | uint48 | 6 |

**Group 4: Lazy pass boon (slots 93-95)**
| Slot | Variable | Type | Bytes Used |
|------|----------|------|------------|
| 93 | lazyPassBoonDay | uint48 | 6 |
| 94 | lazyPassBoonDiscountBps | uint16 | 2 |
| 95 | deityLazyPassBoonDay | uint48 | 6 |

**NOTE: deityBoonDay (72), deityBoonUsedMask (73), deityBoonRecipientDay (74) are NOT per-player boon state** -- they are deity-action tracking (which deity used which slot on which day, and which recipients received boons that day). These are NOT part of the "player boon state" that gets packed. They track the deity's allocation/usage state, not the recipient's boon state.

### Proposed Packed Layout (2 slots per player)

**Bit budget analysis:**

The per-player boon state that needs packing (excluding deity action tracking):

| Field | Current Type | Packed Type | Bits | Notes |
|-------|-------------|-------------|------|-------|
| coinflipBoonBps | uint16 | uint8 (encoded) | 8 | Values: 0/500/1000/2500 -> encode as tier 0-3 |
| coinflipBoonDay | uint48 | uint24 | 24 | 45,000+ year range |
| deityCoinflipBoonDay | uint48 | uint24 | 24 | |
| lootboxBoostTier | 3x bool | uint8 | 8 | 0=none, 1=5%, 2=15%, 3=25% (BOON-05) |
| lootboxBoostDay | 3x uint48 | uint24 | 24 | Single day (tier tracks which level) |
| deityLootboxBoostDay | 3x uint48 | uint24 | 24 | Single deity day |
| purchaseBoostBps | uint16 | uint8 (encoded) | 8 | Values: 0/500/1500/2500 -> encode as tier 0-3 |
| purchaseBoostDay | uint48 | uint24 | 24 | |
| deityPurchaseBoostDay | uint48 | uint24 | 24 | |
| decimatorBoostBps | uint16 | uint8 (encoded) | 8 | Values: 0/1000/2500/5000 -> encode as tier 0-3 |
| deityDecimatorBoostDay | uint48 | uint24 | 24 | (decimator has no time expiry, only deity day) |
| whaleBoonDay | uint48 | uint24 | 24 | |
| whaleBoonDiscountBps | uint16 | uint8 (encoded) | 8 | Values: 0/1000/2500/5000 -> encode as tier 0-3 |
| deityWhaleBoonDay | uint48 | uint24 | 24 | |
| activityBoonPending | uint24 | uint24 | 24 | Already uint24, keep |
| activityBoonDay | uint48 | uint24 | 24 | |
| deityActivityBoonDay | uint48 | uint24 | 24 | |
| deityPassBoonTier | uint8 | uint8 | 8 | Already uint8 (0-3) |
| deityPassBoonDay | uint48 | uint24 | 24 | |
| deityDeityPassBoonDay | uint48 | uint24 | 24 | |
| lazyPassBoonDay | uint48 | uint24 | 24 | |
| lazyPassBoonDiscountBps | uint16 | uint8 (encoded) | 8 | Values: 0/1000/2500/5000 -> encode as tier 0-3 |
| deityLazyPassBoonDay | uint48 | uint24 | 24 | |

**Total: 13 x 24-bit day fields = 312 bits + 7 x 8-bit tier fields = 56 bits + 1 x 24-bit uint24 = 24 bits = 392 bits = 49 bytes**

This fits in 2 slots (64 bytes = 512 bits), with 120 bits (15 bytes) to spare.

### Concrete Struct Definition

```solidity
/// @dev Packed boon state for a single player. 2 storage slots.
///
/// Slot 0 (256 bits):
///   [0-23]    coinflipDay          uint24   Day coinflip boon was awarded
///   [24-47]   deityCoinflipDay     uint24   Deity-source day for coinflip boon
///   [48-55]   coinflipTier         uint8    0=none, 1=5%, 2=10%, 3=25%
///   [56-79]   lootboxBoostDay      uint24   Day lootbox boost was awarded
///   [80-103]  deityLootboxDay      uint24   Deity-source day for lootbox boost
///   [104-111] lootboxBoostTier     uint8    0=none, 1=5%, 2=15%, 3=25%
///   [112-135] purchaseDay          uint24   Day purchase boost was awarded
///   [136-159] deityPurchaseDay     uint24   Deity-source day for purchase boost
///   [160-167] purchaseTier         uint8    0=none, 1=5%, 2=15%, 3=25%
///   [168-175] decimatorTier        uint8    0=none, 1=10%, 2=25%, 3=50%
///   [176-199] deityDecimatorDay    uint24   Deity-source day for decimator
///   [200-223] whaleDay             uint24   Day whale boon was awarded
///   [224-247] deityWhaleDay        uint24   Deity-source day for whale boon
///   [248-255] whaleTier            uint8    0=none, 1=10%, 2=25%, 3=50%
///
/// Slot 1 (256 bits, using 200):
///   [0-23]    activityPending      uint24   Pending activity bonus levels
///   [24-47]   activityDay          uint24   Day activity boon was awarded
///   [48-71]   deityActivityDay     uint24   Deity-source day for activity boon
///   [72-79]   deityPassTier        uint8    0=none, 1=10%, 2=25%, 3=50%
///   [80-103]  deityPassDay         uint24   Day deity pass boon was awarded
///   [104-127] deityDeityPassDay    uint24   Deity-granted deity pass boon day
///   [128-151] lazyPassDay          uint24   Day lazy pass boon was awarded
///   [152-175] deityLazyPassDay     uint24   Deity-source day for lazy pass boon
///   [176-183] lazyPassTier         uint8    0=none, 1=10%, 2=25%, 3=50%
///   [184-199] (unused, 16 bits)
///   [200-255] (unused, 56 bits)
struct BoonPacked {
    uint256 slot0;
    uint256 slot1;
}
```

**Implementation approach:** Use `BitPackingLib.setPacked` or inline shift/mask operations. The project already uses this pattern successfully for `mintPacked_` (256-bit packed word accessed in multiple modules via BitPackingLib).

### Tier Encoding Tables

Each BPS value maps to a tier uint8. Helper pure functions decode back to BPS:

```solidity
// Coinflip: 500 -> 1, 1000 -> 2, 2500 -> 3
// Lootbox boost: 500 -> 1, 1500 -> 2, 2500 -> 3
// Purchase: 500 -> 1, 1500 -> 2, 2500 -> 3
// Decimator: 1000 -> 1, 2500 -> 2, 5000 -> 3
// Whale: 1000 -> 1, 2500 -> 2, 5000 -> 3
// Deity pass: already uint8 tier (1=10%, 2=25%, 3=50%)
// Lazy pass: 1000 -> 1, 2500 -> 2, 5000 -> 3
```

### Read-Modify-Write Pattern

Every boon function follows the same pattern:

```solidity
function consumeCoinflipBoon(address player) external returns (uint16 boonBps) {
    if (player == address(0)) return 0;
    BoonPacked storage bp = boonPacked[player];
    uint256 s0 = bp.slot0;  // 1 SLOAD

    uint8 tier = uint8(s0 >> 48);  // coinflipTier at bits [48-55]
    if (tier == 0) return 0;

    uint48 currentDay = _simulatedDayIndex();
    uint24 deityDay = uint24(s0 >> 24);  // deityCoinflipDay
    if (deityDay != 0 && deityDay != currentDay) {
        // Clear coinflip fields
        s0 = s0 & ~(COINFLIP_MASK);  // zero out bits [0-55]
        bp.slot0 = s0;  // 1 SSTORE
        return 0;
    }
    uint24 stampDay = uint24(s0);  // coinflipDay
    if (stampDay > 0 && currentDay > stampDay + COINFLIP_BOON_EXPIRY_DAYS) {
        s0 = s0 & ~(COINFLIP_MASK);
        bp.slot0 = s0;
        return 0;
    }
    boonBps = _decodeCoinflipBps(tier);
    s0 = s0 & ~(COINFLIP_MASK);
    bp.slot0 = s0;
    return boonBps;
}
```

### Files That Must Change

| File | Changes | Scope |
|------|---------|-------|
| `contracts/storage/DegenerusGameStorage.sol` | Add BoonPacked struct + mapping, mark old mappings with deprecation comments but keep for slot reservation | HIGH - struct definition |
| `contracts/modules/DegenerusGameBoonModule.sol` | Rewrite all 4 consume functions + checkAndClearExpiredBoon | HIGH - full rewrite |
| `contracts/modules/DegenerusGameLootboxModule.sol` | Rewrite _applyBoon, _activeBoonCategory, plus lootbox boost consumption in _rollLootboxBoons | HIGH - major changes |
| `contracts/modules/DegenerusGameWhaleModule.sol` | Rewrite _applyLootboxBoost, whale boon reads in purchaseWhaleBundle, lazy pass boon reads in _purchaseLazyPass, deity pass boon reads in purchaseDeityPass | HIGH - scattered reads |
| `contracts/modules/DegenerusGameMintModule.sol` | Rewrite lootbox boost consumption in _applyLootboxBoost | MEDIUM - one function |
| `contracts/interfaces/IDegenerusGameModules.sol` | No interface changes needed (return types stay uint16) | NONE |
| `contracts/interfaces/IDegenerusGame.sol` | No interface changes needed | NONE |
| `contracts/DegenerusGame.sol` | No changes needed (delegatecalls to modules handle it) | NONE |
| `contracts/DeityBoonViewer.sol` | No changes (reads via deityBoonData which is separate from player boon state) | NONE |

### Critical: Storage Slot Collision Avoidance

The old mappings occupy slots 25-41, 72-82, 85-87, 93-95. The new `mapping(address => BoonPacked)` needs a NEW slot that does not collide with any existing storage. Since this is a delegatecall module pattern, ALL modules share the same storage layout from DegenerusGameStorage.sol.

**Approach:** Add the new `BoonPacked` mapping at the end of the storage declarations in DegenerusGameStorage.sol. The old mappings MUST remain declared (even if unused) to preserve slot numbering for all other variables. They can be commented with `/// @deprecated Replaced by boonPacked` but must not be removed.

### Anti-Patterns to Avoid

- **Removing old storage declarations:** NEVER delete old mapping declarations -- this shifts all subsequent storage slot numbers, breaking every variable after them. The old mappings must stay as slot placeholders.
- **Assembly for packed reads:** Do not use inline assembly for struct field access. Solidity handles struct member access efficiently enough, and assembly introduces audit risk. The project convention is pure Solidity with BitPackingLib helpers.
- **Separate read and write paths:** Every function must load the struct once, modify in memory, and write back once. Do NOT load individual fields in separate SLOADs.
- **Changing external interfaces:** The consume functions return uint16 BPS values. The packed storage uses tier encoding internally but must decode back to BPS at the interface boundary. Do not change the external ABI.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Bit packing helpers | Custom assembly packing | BitPackingLib.setPacked (already exists) | Audited, tested, used in mintPacked_ |
| Tier-to-BPS conversion | Inline ternary chains in every function | Pure internal helper functions (e.g., _coinflipTierToBps) | DRY, testable, one change point |

**Key insight:** The project already has a working bit-packing pattern via BitPackingLib + mintPacked_. The boon packing should follow this exact pattern to maintain consistency and reduce review burden.

## Common Pitfalls

### Pitfall 1: Storage Slot Shift from Removing Old Declarations
**What goes wrong:** Removing the old 32 mapping declarations shifts all subsequent storage slot numbers, silently corrupting every variable declared after them.
**Why it happens:** Solidity assigns storage slots sequentially by declaration order. Mappings each occupy one slot (for the slot seed).
**How to avoid:** Keep all old mapping declarations in place, commented as deprecated. Add the new `boonPacked` mapping at the very end of DegenerusGameStorage.sol.
**Warning signs:** `forge inspect` shows different slot numbers after changes. Any slot that was N and is now N-32 means declarations were removed.

### Pitfall 2: via_ir + optimizer_runs=2 Overhead
**What goes wrong:** With `via_ir = true` and `optimizer_runs = 2`, the compiler optimizes for deployment size, not runtime. Bit masking operations may not be optimized away, adding ~3-20 gas per field access.
**Why it happens:** Low optimizer_runs value tells the compiler "this code runs rarely, optimize for size."
**How to avoid:** Net savings are still overwhelmingly positive (2 SLOADs at 4,200 gas vs 29 SLOADs at 60,900 gas = ~56,700 gas saved, dwarfing any masking overhead). Verify with `forge snapshot --diff`.
**Warning signs:** Gas increases in individual function calls (unlikely but possible for rarely-called paths).

### Pitfall 3: Lootbox Boost Tier Transition Logic
**What goes wrong:** The lootbox boost uses "upgrade only" semantics -- if a player has a 15% boost and rolls 5%, the 15% stays. The current code uses 3 separate bool flags. Converting to a single tier field changes the comparison logic.
**Why it happens:** The old pattern sets/clears 3 bools independently. The new pattern uses `if (newTier > existingTier) existingTier = newTier`.
**How to avoid:** Map the bool triple to a tier consistently: tier 0=none, 1=5%, 2=15%, 3=25%. Then the upgrade logic is simply `max(old, new)`. Deity overwrite logic is: always set regardless of comparison.
**Warning signs:** Test failures in lootbox boost upgrade scenarios.

### Pitfall 4: Deity vs Lootbox Source Tracking
**What goes wrong:** Each boon has two day fields: one for the actual award day and one for deity-source tracking. Deity-sourced boons expire when the day changes (deityDay != currentDay), while lootbox-sourced boons have N-day windows. Confusing the two during packing breaks expiration.
**Why it happens:** Both are "day" fields but have different semantics.
**How to avoid:** Name fields clearly in the struct layout: `coinflipDay` (award day for expiry check) and `deityCoinflipDay` (deity source day, 0 for lootbox-sourced). The pack-unpack code must preserve this dual-day pattern.
**Warning signs:** Deity boons not expiring on day change, or lootbox boons expiring too early.

### Pitfall 5: checkAndClearExpiredBoon Must Clear Both Slots
**What goes wrong:** If the function only writes back slot0 when clearing expired boons, slot1 boons remain dirty.
**Why it happens:** Optimizing for "only write if changed" may skip slot1 if no slot1 fields were expired.
**How to avoid:** Load both slots, check all fields, write back both slots only if either changed. Use a `changed0`/`changed1` flag pattern.
**Warning signs:** Activity/deityPass/lazyPass boons not clearing properly.

### Pitfall 6: Decimator Has No Award Day (Only Deity Day)
**What goes wrong:** Unlike other boons, the decimator boost has no time-based expiry from lootbox source. It only expires via deity day check. Accidentally adding a day-based expiry breaks the decimator boon.
**Why it happens:** The current code has `decimatorBoostBps` + `deityDecimatorBoostDay` but no `decimatorBoostDay`. There is NO award day for decimator.
**How to avoid:** The packed struct must NOT allocate a day field for decimator award. Only store `decimatorTier` and `deityDecimatorDay`. When source is lootbox, `deityDecimatorDay` stays 0 (meaning "never expires via deity check").
**Warning signs:** Test failures where decimator boons expire unexpectedly.

## Code Examples

### Pattern 1: Reading a tier field from packed slot

```solidity
// Extract coinflipTier from slot0 (bits 48-55)
uint8 tier = uint8(s0 >> 48);
// Decode to BPS
uint16 bps = tier == 3 ? 2500 : (tier == 2 ? 1000 : (tier == 1 ? 500 : 0));
```

### Pattern 2: Clearing a boon category within a slot

```solidity
// Clear coinflip fields (bits 0-55: coinflipDay[24] + deityCoinflipDay[24] + coinflipTier[8])
uint256 COINFLIP_CLEAR_MASK = ~(uint256((1 << 56) - 1));  // bits 0-55
s0 = s0 & COINFLIP_CLEAR_MASK;
```

### Pattern 3: Setting a boon with tier and day

```solidity
// Set lootbox boost: tier=2 (15%), day=currentDay, deityDay=0
uint256 s0 = bp.slot0;
// Clear lootbox fields (bits 56-111)
s0 = s0 & ~(uint256((1 << 56) - 1) << 56);
// Set new values
s0 |= (uint256(currentDay) << 56);       // lootboxBoostDay at [56-79]
// deityLootboxDay stays 0 (already cleared)
s0 |= (uint256(2) << 104);               // lootboxBoostTier=2 at [104-111]
bp.slot0 = s0;
```

### Pattern 4: Existing BitPackingLib usage (project convention)

```solidity
// From DegenerusGameBoonModule.consumeActivityBoon (current code)
uint256 prevData = mintPacked_[player];
uint24 levelCount = uint24(
    (prevData >> BitPackingLib.LEVEL_COUNT_SHIFT) & BitPackingLib.MASK_24
);
uint256 data = BitPackingLib.setPacked(
    prevData,
    BitPackingLib.LEVEL_COUNT_SHIFT,
    BitPackingLib.MASK_24,
    newLevelCount
);
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| 1 mapping per field | Packed struct with bit operations | Standard EVM optimization | 29 SLOADs -> 2 SLOADs per checkAndClearExpiredBoon |
| 3 bool flags for lootbox tiers | Single uint8 tier (0-3) | Tier encoding pattern | Eliminates 6 extra mappings (3 bool + 3 redundant day) |

**EVM gas costs (relevant to this optimization):**
- Cold SLOAD: 2,100 gas
- Warm SLOAD: 100 gas
- Cold SSTORE (zero to nonzero): 20,000 gas
- Cold SSTORE (nonzero to zero): refund of 4,800 gas
- Cold SSTORE (nonzero to nonzero): 5,000 gas

**Theoretical savings for checkAndClearExpiredBoon (worst case, all boons active):**
- Before: ~29 cold SLOADs = 60,900 gas + up to 29 cold SSTOREs for clearing
- After: 2 cold SLOADs = 4,200 gas + 2 cold SSTOREs for clearing
- Net SLOAD savings alone: ~56,700 gas per call

## Open Questions

1. **Should BoonPackingLib be a separate library or inline constants?**
   - What we know: BitPackingLib exists and is used for mintPacked_. It defines masks and shifts as constants.
   - What's unclear: Whether boon-specific shift/mask constants should live in BitPackingLib (bloats it) or in a new BoonPackingLib (more files) or inline in BoonModule (less reusable).
   - Recommendation: Define shift/mask constants directly in DegenerusGameStorage.sol alongside the struct, since they are tightly coupled to the layout. This matches how BitPackingLib constants live close to the mintPacked_ definition.

2. **Should _applyLootboxBoost in WhaleModule and MintModule be unified?**
   - What we know: Both WhaleModule and MintModule have near-identical _applyLootboxBoost functions that check 25% -> 15% -> 5% boost in order. After packing, both read the same tier field.
   - What's unclear: Whether to keep the duplication (different module boundaries) or extract a shared helper.
   - Recommendation: Keep separate for now -- the modules are at EIP-170 size limits. The packed version will be much shorter anyway (read tier, decode, clear, write back = ~10 lines vs ~50 lines current).

3. **Decimal precision: does uint24 for day fields lose any information?**
   - What we know: Current fields are uint48 (max 281 trillion). Day indices are computed from block.timestamp / 86400 = approximately 19,000 as of 2026. uint24 max is 16,777,215 (year 47,900+).
   - Recommendation: SAFE. uint24 day fields provide 45,000+ years of range. The requirement explicitly specifies uint24.

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Hardhat (Mocha/Chai) + Foundry (forge test) |
| Config file | hardhat.config.js + foundry.toml |
| Quick run command | `npx hardhat test test/unit/DegenerusGame.test.js test/edge/WhaleBundle.test.js` |
| Full suite command | `npm test && forge test` |

### Phase Requirements -> Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| BOON-01 | Struct replaces 32 mappings, forge inspect validates 2-slot layout | smoke | `forge inspect contracts/DegenerusGame.sol:DegenerusGame storage-layout 2>&1 \| grep boonPacked` | N/A (manual verification) |
| BOON-02 | checkAndClearExpiredBoon loads 2 slots, clears expired, writes back | unit + integration | `npx hardhat test test/unit/DegenerusGame.test.js` | Existing tests cover behavior |
| BOON-03 | _applyBoon writes packed struct correctly for each boon type | integration | `npx hardhat test test/edge/WhaleBundle.test.js` | Existing tests |
| BOON-04 | Consume functions return correct BPS and clear state | unit + integration | `npx hardhat test test/unit/DegenerusGame.test.js test/edge/WhaleBundle.test.js` | Existing tests |
| BOON-05 | Lootbox boost tier encodes 0-3 replacing 3 bools | integration | `npx hardhat test test/edge/WhaleBundle.test.js` | Existing tests cover boost consumption |
| BOON-06 | All existing tests pass | full suite | `npm test && forge test` | All existing test files |

### Sampling Rate
- **Per task commit:** `npx hardhat test test/unit/DegenerusGame.test.js test/edge/WhaleBundle.test.js`
- **Per wave merge:** `npm test && forge test`
- **Phase gate:** Full suite green before `/gsd:verify-work`

### Wave 0 Gaps
None -- existing test infrastructure covers all phase requirements. The boon consumption paths are already tested through:
- `test/unit/DegenerusGame.test.js` -- consumeCoinflipBoon/consumeDecimatorBoon access control
- `test/edge/WhaleBundle.test.js` -- whale boon pricing, lazy pass boon pricing, lootbox boost consumption, deity boon issuance and expiry
- `test/access/AccessControl.test.js` -- boon function access control
- `test/validation/PaperParity.test.js` -- boon reward parity
- `test/fuzz/PrecisionBoundary.t.sol` -- boon budget precision
- `test/fuzz/DeployCanary.t.sol` -- boon module deployment address

## Sources

### Primary (HIGH confidence)
- `forge inspect contracts/DegenerusGame.sol:DegenerusGame storage-layout` -- all 32 boon slot numbers verified
- Direct code reading: DegenerusGameStorage.sol, DegenerusGameBoonModule.sol, DegenerusGameLootboxModule.sol, DegenerusGameWhaleModule.sol, DegenerusGameMintModule.sol
- `.planning/milestones/v3.3-phases/47-gas-optimization/47-01-gas-analysis.md` -- prior packing analysis with gas cost methodology

### Secondary (MEDIUM confidence)
- EVM gas costs from Ethereum yellow paper and EIP-2929 (cold/warm access costs) -- well-established, no verification needed

### Tertiary (LOW confidence)
None.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - existing project stack, no new dependencies
- Architecture: HIGH - code directly read, slot numbers verified via forge inspect, bit layout manually computed and verified to fit 2 slots
- Pitfalls: HIGH - derived from direct code analysis, prior gas analysis in project, and understanding of Solidity storage model

**Research date:** 2026-03-22
**Valid until:** 2026-04-22 (stable domain -- EVM storage model and Solidity 0.8 packing rules do not change)
