# Phase 74: Storage Foundation - Research

**Researched:** 2026-03-22
**Domain:** Solidity storage layout, bitwise key encoding, mapping collision analysis
**Confidence:** HIGH

## Summary

Phase 74 adds a third key space for far-future ticket queue entries to DegenerusGameStorage. The existing double-buffer system uses bit 23 of a uint24 key to distinguish write/read slots, leaving bits 0-22 for the level value. The proposal reserves bit 22 (1 << 22 = 4,194,304) as TICKET_FAR_FUTURE_BIT, creating a third disjoint key range that cannot collide with either double-buffer slot for any reachable level value.

This is a constants-and-helper-only change -- no storage variables are added, no slot layout changes, no new mappings. The new constant and helper function share the existing `ticketQueue` and `ticketsOwedPacked` mappings using a key that is provably disjoint from both existing key spaces. The change is isolated to DegenerusGameStorage.sol and compiles as part of the existing inheritance chain (DegenerusGame, all delegatecall modules).

**Primary recommendation:** Add TICKET_FAR_FUTURE_BIT constant (uint24, 1 << 22) adjacent to the existing TICKET_SLOT_BIT constant, and add `_tqFarFutureKey(uint24 lvl) internal pure returns (uint24)` as a simple bitwise OR helper next to the existing `_tqWriteKey` and `_tqReadKey` functions. No other changes are needed for this phase.

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| STORE-01 | TICKET_FAR_FUTURE_BIT constant (1 << 22) exists in DegenerusGameStorage with _tqFarFutureKey(lvl) helper | Key space analysis proves bit 22 is available; placement pattern follows existing TICKET_SLOT_BIT; helper follows _tqWriteKey/_tqReadKey pattern |
| STORE-02 | Three key spaces (Slot 0, Slot 1, Far Future) are non-colliding for all valid level values | Formal proof by range analysis: three uint24 ranges are disjoint for all lvl < 2^22; game cannot reach level 2^22 in practice |
</phase_requirements>

## Architecture Patterns

### Existing Key Space Layout (uint24)

The ticket queue system uses `mapping(uint24 => address[]) ticketQueue` and `mapping(uint24 => mapping(address => uint40)) ticketsOwedPacked` with bitwise-encoded keys:

```
uint24 key space (24 bits total):

  Bit 23 (MSB)     Bit 22          Bits 21-0
  ┌─────────┐   ┌─────────┐   ┌──────────────────┐
  │SLOT_BIT │   │  (new)  │   │   level value     │
  │ 1 << 23 │   │FF_BIT   │   │   0 to 4,194,303 │
  └─────────┘   │ 1 << 22 │   └──────────────────┘
                └─────────┘

Current key spaces (two):
  Slot 0:  0b_0_?_LLLLLLLLLLLLLLLLLLLLLL  (0x000000 - 0x3FFFFF when bit 22 unused)
  Slot 1:  0b_1_?_LLLLLLLLLLLLLLLLLLLLLL  (0x800000 - 0xBFFFFF when bit 22 unused)

Proposed third key space:
  FF:      0b_0_1_LLLLLLLLLLLLLLLLLLLLLL  (0x400000 - 0x7FFFFF)
```

### Collision-Free Proof

For any level value `lvl` where bits 22 and 23 are both zero (i.e., lvl < 4,194,304):

| Key Function | Bit 23 | Bit 22 | Range | When Used |
|---|---|---|---|---|
| `_tqWriteKey(lvl)` when slot=0 | 0 | 0 | 0x000000 - 0x3FFFFF | Near-future writes (slot 0 active) |
| `_tqWriteKey(lvl)` when slot=1 | 1 | 0 | 0x800000 - 0xBFFFFF | Near-future writes (slot 1 active) |
| `_tqReadKey(lvl)` when slot=0 | 1 | 0 | 0x800000 - 0xBFFFFF | Near-future reads (slot 0 active) |
| `_tqReadKey(lvl)` when slot=1 | 0 | 0 | 0x000000 - 0x3FFFFF | Near-future reads (slot 1 active) |
| `_tqFarFutureKey(lvl)` (new) | 0 | 1 | 0x400000 - 0x7FFFFF | Far-future (slot-independent) |

The three ranges 0x000000-0x3FFFFF, 0x400000-0x7FFFFF, and 0x800000-0xBFFFFF are disjoint. No level value can produce a collision because the discriminating bits (22 and 23) are set by the key function, not by the level.

**Level safety bound:** Level must remain below 2^22 = 4,194,304. The existing TICKET_SLOT_BIT comment states "Max real level: 2^23 - 1 = 8,388,607 (game would take millennia)." The new bit 22 halves the theoretical max to 2^22 - 1 = 4,194,303. This still requires millennia -- each level takes multiple days minimum (purchase phase + 5 jackpot days). Even at 1 level per day, reaching level 4 million would take ~11,500 years.

### Pattern: Helper Function Style

The existing helpers follow a consistent pattern in DegenerusGameStorage.sol:

```solidity
// Source: contracts/storage/DegenerusGameStorage.sol lines 696-705

/// @dev Compute the ticket queue key for the write slot.
///      Slot 0 uses raw level, slot 1 sets bit 23.
function _tqWriteKey(uint24 lvl) internal view returns (uint24) {
    return ticketWriteSlot != 0 ? lvl | TICKET_SLOT_BIT : lvl;
}

/// @dev Compute the ticket queue key for the read slot (opposite of write).
function _tqReadKey(uint24 lvl) internal view returns (uint24) {
    return ticketWriteSlot == 0 ? lvl | TICKET_SLOT_BIT : lvl;
}
```

The new helper follows the same style but is simpler (no slot-awareness needed):

```solidity
/// @dev Compute the ticket queue key for the far-future key space.
///      Always sets bit 22, independent of ticketWriteSlot.
function _tqFarFutureKey(uint24 lvl) internal pure returns (uint24) {
    return lvl | TICKET_FAR_FUTURE_BIT;
}
```

Note: `_tqFarFutureKey` is `pure` (not `view`) because it does not read `ticketWriteSlot`. This is correct because far-future tickets are not double-buffered -- they exist in a single, persistent key space that is drained by `processFutureTicketBatch` independently of the slot swap cycle.

### Constant Placement

```solidity
// In the CONSTANTS section of DegenerusGameStorage.sol, after TICKET_SLOT_BIT:

/// @dev Bit mask for ticket queue double-buffer key encoding.
///      Set bit 23 of the uint24 level key to distinguish write/read slots.
///      Max real level: 2^22 - 1 = 4,194,303 (game would take millennia).
uint24 internal constant TICKET_SLOT_BIT = 1 << 23;

/// @dev Bit mask for far-future ticket key encoding.
///      Set bit 22 of the uint24 level key to create a third key space
///      disjoint from both double-buffer slots.
///      Used for tickets targeting levels > currentLevel + 6.
uint24 internal constant TICKET_FAR_FUTURE_BIT = 1 << 22;
```

**Important:** The TICKET_SLOT_BIT comment should be updated from "Max real level: 2^23 - 1" to "Max real level: 2^22 - 1" since the new bit 22 reservation reduces the level address space.

### Anti-Patterns to Avoid

- **Making _tqFarFutureKey `view`:** Unlike write/read keys, far-future keys do not depend on ticketWriteSlot. Using `view` would be misleading and slightly more expensive (SLOAD for ticketWriteSlot).
- **Adding a storage variable:** This phase must NOT add any storage variables. DegenerusGameStorage uses append-only storage with delegatecall modules that must share identical slot layout. Constants and `pure`/`view` functions are safe additions.
- **Double-buffering the FF key:** Far-future tickets are not part of the near-future double-buffer cycle. They have their own drain path (processFutureTicketBatch). Adding slot-awareness to the FF key would create unnecessary complexity and is not required by any subsequent phase.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Key encoding | Custom bit packing | Simple bitwise OR with constant | Bitwise OR on uint24 is atomic, gas-free in practice, and trivially verifiable |
| Collision testing | Manual enumeration | Range analysis on bit positions | The three ranges are provably disjoint by construction; enumeration is not necessary |

## Common Pitfalls

### Pitfall 1: Forgetting to Update the Max Level Comment
**What goes wrong:** The TICKET_SLOT_BIT NatSpec says "Max real level: 2^23 - 1 = 8,388,607". After reserving bit 22, the actual max is 2^22 - 1 = 4,194,303.
**Why it happens:** The constant value doesn't change, only its interaction with the new bit.
**How to avoid:** Update the TICKET_SLOT_BIT comment in the same commit that adds TICKET_FAR_FUTURE_BIT.
**Warning signs:** Stale comment during code review.

### Pitfall 2: Accidentally Making the Helper `view`
**What goes wrong:** If `_tqFarFutureKey` is `view`, the compiler may generate a SLOAD even though the function doesn't need storage access. This wastes gas and is semantically wrong.
**Why it happens:** Copy-pasting from `_tqWriteKey`/`_tqReadKey` which are `view` because they read `ticketWriteSlot`.
**How to avoid:** The helper is a simple bitwise OR on its argument -- `pure` is the correct visibility.
**Warning signs:** `view` keyword without any storage read.

### Pitfall 3: Adding Storage Variables in This Phase
**What goes wrong:** Any new storage variable shifts all subsequent slot indices, breaking the delegatecall module pattern. Every module (AdvanceModule, JackpotModule, MintModule, LootboxModule, EndgameModule, etc.) inherits DegenerusGameStorage. A slot shift would cause silent storage corruption.
**Why it happens:** Temptation to add a flag or counter for far-future tracking.
**How to avoid:** This phase is constants + pure helper ONLY. Storage additions (if needed for later phases) must be append-only and carefully coordinated.
**Warning signs:** Any `internal` non-constant variable declaration in the diff.

### Pitfall 4: Using a Bit Below 22 for FF Key
**What goes wrong:** If bit 21 or lower were used, valid level values above 2^21 (2,097,152) would collide with the FF key range. While still "millennia away," it halves the safety margin unnecessarily.
**Why it happens:** Premature optimization of the level address space.
**How to avoid:** Bit 22 is the correct choice -- it's the next-highest available bit below the existing bit 23, maximizing the level address space at 2^22 - 1 = 4,194,303.
**Warning signs:** FF_BIT constant is not 1 << 22.

## Code Examples

### Complete Implementation (Verified Pattern)

The following is the complete set of changes needed for STORE-01 and STORE-02:

```solidity
// contracts/storage/DegenerusGameStorage.sol

// 1. Add constant after TICKET_SLOT_BIT (line ~154):

/// @dev Bit mask for far-future ticket key encoding.
///      Set bit 22 of the uint24 level key to create a third key space
///      disjoint from both double-buffer slots (bit 23).
///      Far-future = tickets targeting > currentLevel + 6.
///      Three key spaces: Slot0 [0x000000-0x3FFFFF], FF [0x400000-0x7FFFFF],
///      Slot1 [0x800000-0xBFFFFF]. Disjoint for all lvl < 2^22.
uint24 internal constant TICKET_FAR_FUTURE_BIT = 1 << 22;

// 2. Add helper after _tqReadKey (line ~705):

/// @dev Compute the ticket queue key for the far-future key space.
///      Always sets bit 22, independent of ticketWriteSlot.
///      Far-future tickets are not double-buffered; they persist until
///      drained by processFutureTicketBatch.
function _tqFarFutureKey(uint24 lvl) internal pure returns (uint24) {
    return lvl | TICKET_FAR_FUTURE_BIT;
}

// 3. Update TICKET_SLOT_BIT comment (line ~151-153):
// Change "Max real level: 2^23 - 1 = 8,388,607"
// To:    "Max real level: 2^22 - 1 = 4,194,303"
```

### Downstream Usage Preview (NOT Part of This Phase)

For context on how the new helper will be consumed in later phases:

```solidity
// Phase 75: Routing (_queueTickets modification)
uint24 key = (targetLevel > level + 6)
    ? _tqFarFutureKey(targetLevel)
    : _tqWriteKey(targetLevel);

// Phase 76: Processing (processFutureTicketBatch modification)
uint24 ffk = _tqFarFutureKey(lvl);
address[] storage ffQueue = ticketQueue[ffk];

// Phase 77: Jackpot (_awardFarFutureCoinJackpot modification)
uint24 ffk = _tqFarFutureKey(candidate);
address[] storage ffQueue = ticketQueue[ffk];
uint256 ffLen = ffQueue.length;
// Combined pool: len (write-side) + ffLen (far-future)
```

## Callers of _queueTickets/_queueTicketsScaled (Reference for Later Phases)

All write paths that push into ticketQueue -- the planner for Phase 75 will need this list:

| Caller | File | Function | targetLevel Source |
|---|---|---|---|
| Constructor pre-queue | DegenerusGame.sol:252-253 | constructor | levels 1-100 (fixed) |
| Vault perpetual | AdvanceModule.sol:1224-1232 | _processPhaseTransition | purchaseLevel + 99 (always far-future) |
| Lootbox ETH | LootboxModule.sol:988 | _resolveLootboxCommon | _rollTargetLevel: 95% near (0-5), 5% far (5-50) |
| Lootbox whale pass | LootboxModule.sol:1117 | whale pass within lootbox | ticket range over 100 levels |
| Whale purchase | WhaleModule.sol:270,425,540 | claimWhalePass/purchaseWhale | 100-level range |
| Endgame | EndgameModule.sol:286 | _processEndgame | calculated targetLevel |
| Decimator | DecimatorModule.sol:391 | _processDecimator | calculated targetLevel |
| Jackpot auto-rebuy | JackpotModule.sol:848 | within ETH jackpot | baseLevel + levelOffset |
| Jackpot ticket rebuy | JackpotModule.sol:1008 | within ticket jackpot | calc.targetLevel |
| Jackpot lvl+1 rebuy | JackpotModule.sol:1210 | ticket processing | lvl + 1 |
| MintModule ticket call | MintModule.sol:1020 | _callTicketPurchase | ticketLevel (near-future) |

## Inheritance Chain Verification

DegenerusGameStorage is `abstract` and inherited by all these contracts. Constants and `pure` functions added to the abstract contract are safe for the delegatecall pattern because:

1. **Constants** compile to inline bytecode values -- they occupy no storage slots.
2. **Pure functions** have no SLOAD/SSTORE -- they cannot interact with storage layout.
3. **No new storage variables** means no slot shift.

Inheriting contracts (verified via grep):
- DegenerusGame (main proxy)
- DegenerusGameAdvanceModule
- DegenerusGameJackpotModule (via PayoutUtils)
- DegenerusGameMintModule
- DegenerusGameLootboxModule
- DegenerusGameEndgameModule
- DegenerusGameDecimatorModule (via PayoutUtils)
- DegenerusGameDegeneretteModule
- DegenerusGameWhaleModule
- DegenerusGameBoonModule
- DegenerusGameGameOverModule

All will pick up the new constant and helper at compilation with zero runtime impact on existing behavior.

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Foundry (forge 1.5.1-stable) + Hardhat 2.28.6 |
| Config file | foundry.toml (Foundry), hardhat.config.js (Hardhat) |
| Quick run command | `npx hardhat compile` (verify compilation) |
| Full suite command | `npx hardhat test` |

### Phase Requirements -> Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| STORE-01 | Constant and helper exist, compile cleanly | compilation | `npx hardhat compile` | N/A (compilation test) |
| STORE-02 | Three key spaces non-colliding | manual proof | Verify in code review; formal proof by range analysis documented above | N/A (mathematical proof) |

### Sampling Rate
- **Per task commit:** `npx hardhat compile` (must succeed)
- **Per wave merge:** Full test suite `npx hardhat test`
- **Phase gate:** Compilation + existing test suite passes (no new tests needed for this phase)

### Wave 0 Gaps
None -- this phase adds only a constant and a pure helper. Compilation success is the primary validation. The non-collision proof is mathematical, documented in this research. Unit tests for the far-future key system will be added in Phase 80.

## Open Questions

1. **Should _tqFarFutureKey also be available in the interface?**
   - What we know: IDegenerusGameModules.sol exposes processFutureTicketBatch but the key functions are internal to storage
   - What's unclear: Whether later phases will need to call _tqFarFutureKey from the main game contract via delegatecall or only within modules
   - Recommendation: Keep it `internal` for now (matches existing _tqWriteKey/_tqReadKey pattern). If interface exposure is needed, it can be added in Phase 75 or 76 without affecting Phase 74.

## Sources

### Primary (HIGH confidence)
- contracts/storage/DegenerusGameStorage.sol -- direct code analysis of TICKET_SLOT_BIT, _tqWriteKey, _tqReadKey, ticketQueue mapping
- contracts/modules/DegenerusGameJackpotModule.sol -- _awardFarFutureCoinJackpot at line 2522 (TQ-01 bug site)
- contracts/modules/DegenerusGameAdvanceModule.sol -- vault perpetual ticket path at line 1223
- contracts/modules/DegenerusGameLootboxModule.sol -- _rollTargetLevel at line 818

### Secondary (MEDIUM confidence)
- audit/v3.8-commitment-window-inventory.md -- TQ-01 vulnerability documentation at line 3522

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH -- no new libraries, pure Solidity constant + function addition
- Architecture: HIGH -- key space math is deterministic; three ranges are provably disjoint by bit-position analysis
- Pitfalls: HIGH -- identified from direct code analysis of the storage pattern and delegatecall architecture

**Research date:** 2026-03-22
**Valid until:** Indefinite (Solidity bitwise operations are not version-sensitive; valid as long as uint24 remains the key type)
