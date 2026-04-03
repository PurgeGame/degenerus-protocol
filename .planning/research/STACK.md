# Stack Research: Storage Repacking & Module Consolidation

**Domain:** Solidity delegatecall storage layout manipulation (non-upgradeable)
**Researched:** 2026-04-02
**Confidence:** HIGH

## Recommended Stack

### Core Technologies

| Technology | Version | Purpose | Why Recommended |
|------------|---------|---------|-----------------|
| Solidity | 0.8.34 | Smart contract language | Already in use; 0.8.34 packing rules are stable and well-documented |
| Foundry (forge) | nightly | `forge inspect` for layout verification, `forge test` for fuzz testing | Already in use; `forge inspect storage-layout` is the canonical tool for slot verification |
| Hardhat | existing | Integration test suite | Already in use; 1455+ tests provide regression safety net |

### Verification Tools

| Tool | Purpose | When to Use |
|------|---------|-------------|
| `forge inspect <Contract> storage-layout` | Dump slot/offset/size for every storage variable | After EVERY storage reorder -- run on DegenerusGameStorage, DegenerusGame, and ALL modules |
| `forge inspect --json` + diff script | Machine-readable layout comparison pre/post change | Create a snapshot before repacking, diff after to confirm only intended slot shifts |
| `vm.load` / `vm.store` in Foundry tests | Direct slot reads/writes for state injection | Already used in 11+ test files; all hardcoded offsets MUST be updated post-repack |
| `forge test --match-contract StorageFoundation` | Existing storage layout assertions | Run immediately after repack to catch misalignment |

### Development Tools

| Tool | Purpose | Notes |
|------|---------|-------|
| `forge inspect` JSON diff | Verify slot shifts are intentional | Pipe `--json` output to `jq` or Python, diff old vs new layout |
| `forge test -vvvv` | Trace failing tests to see exact storage reads | Use when a test fails post-repack to identify which hardcoded offset broke |

## Solidity 0.8.34 Storage Packing Rules

These are the compiler rules that govern the repack. All are stable since Solidity 0.5+ and confirmed in 0.8.x:

### Rule 1: Sequential packing, low-to-high bytes within a slot
Variables declared sequentially pack into the same 32-byte slot if they fit. The first variable occupies byte offset 0, the next occupies the byte immediately after, etc.

### Rule 2: A variable that doesn't fit starts a new slot
If adding a variable would exceed 32 bytes, it begins a new slot at offset 0.

### Rule 3: Value types pack; reference types don't
`uint256`, `mapping`, `array`, and `struct` always start a new slot. Small value types (`bool`, `uint8`, `uint16`, `uint24`, `uint48`, `address`) pack together.

### Rule 4: Structs are padded to full slots in storage
A struct's members pack internally, but the struct itself starts at a new slot boundary. If a struct has 3 bytes of members, it still occupies a full slot.

### Rule 5: Declaration order = slot assignment order
The ONLY way to control layout is variable declaration order. There is no layout pragma. Reordering declarations reorders slots.

### Rule 6: Constants and immutables do NOT consume storage slots
`constant` values are inlined at compile time. `immutable` values are stored in code, not storage. Neither affects the slot layout. This project uses `constant` interfaces (coin, coinflip, etc.) which correctly occupy zero slots.

## Repack Strategy: What Works in This Architecture

### Pre-deployment context (critical simplification)
This is a non-upgradeable, not-yet-deployed contract. There is NO live storage to migrate. The repack is purely a source-code reordering exercise verified by the compiler and tests. This eliminates the entire class of "storage migration" concerns that apply to proxy/upgradeable contracts.

### The safe repack procedure

1. **Snapshot current layout:** `forge inspect DegenerusGameStorage storage-layout --json > /tmp/layout-before.json`
2. **Reorder variables in DegenerusGameStorage.sol** -- the single source of truth
3. **Snapshot new layout:** `forge inspect DegenerusGameStorage storage-layout --json > /tmp/layout-after.json`
4. **Diff the snapshots** -- confirm only intended variables shifted
5. **Verify ALL inheritors match** -- run `forge inspect` on DegenerusGame and every module; slot numbers must be identical to DegenerusGameStorage
6. **Update hardcoded slot constants in Foundry tests** (see blast radius below)
7. **Run full test suite** -- both Hardhat and Foundry
8. **Update slot header comments** in DegenerusGameStorage.sol

### Why this works for delegatecall modules
All modules (EndgameModule, JackpotModule, MintModule, etc.) inherit DegenerusGameStorage as their first parent. Because Solidity assigns slots based on declaration order in the inheritance chain, and all modules share the same single parent storage contract, they automatically get identical layouts. The compiler enforces this -- there is nothing manual to align.

**The only risk:** a module declaring its own storage variable (which would collide). This is already documented as forbidden in the storage contract's NatSpec, and no modules do it.

## Current Layout Analysis (Slots 0-2)

### Slot 0 (30/32 bytes used)
```
[0:6]   levelStartTime           uint48
[6:12]  dailyIdx                 uint48
[12:18] rngRequestTime           uint48
[18:21] level                    uint24
[21:22] jackpotPhaseFlag         bool
[22:23] jackpotCounter           uint8
[23:24] lastPurchaseDay          bool
[24:25] decWindowOpen            bool
[25:26] rngLockedFlag            bool
[26:27] phaseTransitionActive    bool
[27:28] gameOver                 bool
[28:29] dailyJackpotCoinTicketsPending  bool
[29:30] compressedJackpotFlag    uint8
-- 2 bytes padding --
```

### Slot 1 (10/32 bytes used -- 22 bytes wasted)
```
[0:6]   purchaseStartDay         uint48
[6:7]   ticketWriteSlot          uint8
[7:8]   ticketsFullyProcessed    bool
[8:9]   prizePoolFrozen          bool
[9:10]  gameOverPossible         bool
-- 22 bytes padding --
```

### Slot 2 (32/32 bytes)
```
[0:32]  currentPrizePool         uint256
```

### Proposed repack target (from PROJECT.md)
- Move `ticketsFullyProcessed` + `gameOverPossible` into slot 0 (2 bytes padding available)
- Downsize `currentPrizePool` to `uint128` and pack into slot 1 (22 bytes available)
- Eliminate slot 2 entirely

### Feasibility check
Slot 0 has 2 bytes free. `ticketsFullyProcessed` (1 byte) + `gameOverPossible` (1 byte) = 2 bytes. **Exact fit.** Slot 0 becomes 32/32 bytes.

Slot 1 currently has purchaseStartDay (6) + ticketWriteSlot (1) + prizePoolFrozen (1) = 8 bytes after removing the two moved bools. Adding currentPrizePool as uint128 (16 bytes) = 24 bytes. **Fits with 8 bytes padding.**

**uint128 safety for currentPrizePool:** uint128 max = ~3.4e38 wei = ~3.4e20 ETH. Total ETH supply is ~120M ETH = 1.2e26 wei. uint128 exceeds total ETH supply by 12 orders of magnitude. Safe.

### Gas implications of the repack
- **Slot 0 reads that also need ticketsFullyProcessed or gameOverPossible:** Currently cost 2 SLOADs (slot 0 + slot 1). After repack: 1 SLOAD. Saves 2,100 gas (cold) or 100 gas (warm) per co-read.
- **currentPrizePool reads co-occurring with slot 1 fields:** Currently cost 2 SLOADs. After repack: 1 SLOAD. Same savings.
- **currentPrizePool writes:** uint128 writes to a packed slot require a read-modify-write (SLOAD + mask + SSTORE) instead of a direct SSTORE. However, if any other slot 1 field is already loaded in the same function, the SLOAD is free (warm). Net effect depends on access patterns -- likely neutral or slightly positive.

## Blast Radius: Hardcoded Slot References in Tests

These files use `vm.load`/`vm.store` with hardcoded EVM slot numbers and byte offsets. ALL must be audited and updated after the repack.

### Slot 0 references (byte offsets change if ticketsFullyProcessed + gameOverPossible are appended)
| File | What it accesses | Constants to update |
|------|-----------------|---------------------|
| `test/fuzz/TicketLifecycle.t.sol` | jackpotPhaseFlag, jackpotCounter, rngLockedFlag, compressedJackpotFlag, ticketsFullyProcessed | SLOT_0, all `*_SHIFT` constants, SLOT_1 offset for ticketsFullyProcessed |
| `test/fuzz/AffiliateDgnrsClaim.t.sol` | slot 0 bitwise manipulation | Hardcoded shift values |

### Slot 1 references (variables move, offsets change)
| File | What it accesses | Constants to update |
|------|-----------------|---------------------|
| `test/fuzz/DegeneretteFreezeResolution.t.sol` | prizePoolFrozen at FROZEN_BYTE_OFFSET | SLOT_1, FROZEN_BYTE_OFFSET |
| `test/fuzz/StorageFoundation.t.sol` | slot 1 reads for layout assertions | slot 1 expectations |

### Slot 2 elimination -- downstream slot shifts
**CRITICAL:** If slot 2 is eliminated, every variable currently at slot N >= 3 shifts to slot N-1. This affects every test file that hardcodes a slot number >= 3:

| File | Hardcoded slot reference | New slot number |
|------|--------------------------|-----------------|
| `test/fuzz/TicketLifecycle.t.sol` | ticketsOwedPacked (slot 16) | slot 15 |
| `test/fuzz/TicketLifecycle.t.sol` | lootboxRngWordByIndex (slot 45) | slot 44 |
| `test/fuzz/BafRebuyReconciliation.t.sol` | prizePoolsPacked | shifts -1 |
| `test/fuzz/FarFutureIntegration.t.sol` | ticketQueue, prizePoolsPacked | shifts -1 |
| `test/fuzz/VRFStallEdgeCases.t.sol` | totalFlipReversals, midDayTicketRngPending | shifts -1 |
| `test/fuzz/VRFCore.t.sol` | slot references | shifts -1 |
| `test/fuzz/LootboxRngLifecycle.t.sol` | slot references | shifts -1 |
| `test/fuzz/LootboxBoonCoexistence.t.sol` | SLOT_LOOTBOX_EV | shifts -1 |
| `test/fuzz/handlers/CompositionHandler.sol` | mintPacked_ at slot 12 | slot 11 |
| `test/fuzz/handlers/VRFPathHandler.sol` | slot references | shifts -1 |

### Mitigation: Centralize slot constants
Rather than hardcoding `uint256(0)`, `uint256(1)`, etc. in each test file, define named constants in a shared test helper. This makes future repacks a single-point-of-change:

```solidity
// test/helpers/SlotConstants.sol
library SlotConstants {
    uint256 constant SLOT_FSM = 0;             // timing + FSM + flags
    uint256 constant SLOT_BUFFER_PRIZE = 1;    // double-buffer + currentPrizePool
    uint256 constant SLOT_PRIZE_PACKED = 2;    // prizePoolsPacked (was slot 3)
    uint256 constant SLOT_RNG_WORD = 3;        // rngWordCurrent (was slot 4)
    // ... all slots derived from forge inspect
}
```

**Trade-off:** This adds a maintenance file but eliminates the N-file blast radius for any future repack. Worth it given 11+ affected test files.

## Module Consolidation: EndgameModule Elimination

### No special tooling needed
EndgameModule elimination is a pure code-move operation:
- Move function bodies from EndgameModule into target modules
- Update `delegatecall` targets in DegenerusGame.sol
- Delete EndgameModule.sol
- Remove EndgameModule from DegenerusGameStorage NatSpec header

The compiler enforces that moved functions still access the same storage slots (because the target module inherits the same DegenerusGameStorage). No slot manipulation is involved in the module consolidation itself.

### Verification
- `forge inspect` on the receiving modules confirms layout unchanged
- All existing tests for the moved functions continue to pass (they call through DegenerusGame, not directly on the module)

## What NOT to Use

| Avoid | Why | Use Instead |
|-------|-----|-------------|
| `solc --storage-layout` directly | Foundry wraps this with better output formatting and project-aware compilation | `forge inspect` |
| Manual slot counting | Error-prone for 73-slot layouts; compiler is authoritative | `forge inspect --json` + diff |
| Assembly sload/sstore for repacked slots in production | No production code uses raw assembly on slots 0-2; keep it that way | Normal Solidity variable access |
| EIP-1967 / proxy storage patterns | Not applicable -- non-upgradeable architecture | Direct inheritance-based layout |
| Storage gaps (`uint256[50] __gap`) | Anti-pattern for non-upgradeable contracts; wastes deploy gas | Not needed |

## Verification Checklist (post-repack)

```bash
# 1. Snapshot before (do this BEFORE any changes)
forge inspect DegenerusGameStorage storage-layout --json > /tmp/layout-before.json

# 2. After repack, snapshot again
forge inspect DegenerusGameStorage storage-layout --json > /tmp/layout-after.json

# 3. Verify all modules match the storage contract
for contract in DegenerusGame DegenerusGameEndgameModule DegenerusGameJackpotModule \
    DegenerusGameMintModule DegenerusGameAdvanceModule DegenerusGameLootboxModule \
    DegenerusGameWhaleModule DegenerusGameBoonModule DegenerusGameDecimatorModule \
    DegenerusGameDegeneretteModule DegenerusGameGameOverModule; do
  echo "=== $contract ==="
  forge inspect "$contract" storage-layout 2>/dev/null | head -5
done

# 4. Run full test suites
forge test
npx hardhat test
```

## Assembly Access Audit (Slots 0-2)

**Finding:** No production contract uses inline assembly (`sload`/`sstore`) to access EVM slots 0, 1, or 2 directly. All assembly blocks in `contracts/` target:
- `traitBurnTicket` mapping slot computation (JackpotModule, MintModule)
- `delegatecall` result forwarding (Game, AdvanceModule)
- `decBurn` struct offset (DecimatorModule)

This means the repack affects production code ONLY through Solidity-level variable name resolution, which the compiler handles automatically. The blast radius is confined to test files with hardcoded slot numbers.

## Sources

- DegenerusGameStorage.sol lines 1-360 -- slot layout documentation and packing comments (HIGH confidence, primary source)
- `forge inspect DegenerusGameStorage storage-layout` output -- authoritative compiler-generated layout (HIGH confidence)
- 11 Foundry test files using `vm.load`/`vm.store` with hardcoded slot numbers -- blast radius analysis (HIGH confidence, direct code inspection)
- Solidity documentation on storage layout -- packing rules stable since 0.5+ (HIGH confidence)
- PROJECT.md v16.0 milestone description -- repack targets (HIGH confidence, project specification)

---
*Stack research for: Storage repacking and module consolidation in Solidity 0.8.34 delegatecall architecture*
*Researched: 2026-04-02*
