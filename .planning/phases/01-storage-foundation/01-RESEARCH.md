# Phase 1: Storage Foundation - Research

**Researched:** 2026-03-11
**Domain:** Solidity storage layout engineering (EVM slot packing, delegatecall-safe storage, bit-encoded mapping keys)
**Confidence:** HIGH

## Summary

Phase 1 adds three new boolean/uint8 fields to Slot 1, replaces two full-slot uint256 pool variables with a single packed uint256 (uint128+uint128), adds a second packed pending-pool slot, introduces a bit-23 key encoding constant and two helper functions for double-buffer queue keys, and adds swap/freeze/unfreeze helper functions. All changes are confined to `DegenerusGameStorage.sol`.

The most critical finding is a **discrepancy between the source code ASCII comments and the actual compiled storage layout**. The ASCII diagram in the source says Slot 1 has 14 bytes of padding starting at byte 18, but `forge inspect` shows Slot 1 actually has only 8 bytes of padding starting at byte 24 (because `price` is uint128 = 16 bytes filling offsets 8-23). The three new fields must go at Slot 1 offsets 24-26, not 18-20. The ASCII diagrams must be corrected as part of this phase.

The second major concern is that removing `nextPrizePool` and `futurePrizePool` declarations breaks 101 references across 11 files. The locked decision says "replaces in-place" and "removed entirely," but doing so without migrating all consumers causes compile failure. The planner must resolve this tension -- options are detailed in Open Questions.

**Primary recommendation:** Verify ALL storage byte offsets against `forge inspect` output, not the source comments. Place new fields at Slot 1 offsets 24, 25, 26. For the pool migration, the planner must decide between keeping old vars temporarily or migrating all 101 references as part of Phase 1.

<user_constraints>

## User Constraints (from CONTEXT.md)

### Locked Decisions
- Field order: `ticketWriteSlot` (uint8) at byte 18, `ticketsFullyProcessed` (bool) at byte 19, `prizePoolFrozen` (bool) at byte 20 -- exactly as the plan specifies
- Full NatSpec documentation matching existing Slot 1 field style (4-5 lines each with @dev, purpose, security notes)
- Update BOTH the top-of-file overview ASCII diagram (lines ~49-66) AND the inline section header comment near the variable declarations
- `prizePoolsPacked` replaces `nextPrizePool` in-place (currently slot ~5, line 308) -- keeps it near `currentPrizePool`
- `prizePoolPendingPacked` goes immediately after `prizePoolsPacked` -- adjacent packed pool slots
- `futurePrizePool` declaration (line 409) removed entirely -- no comment placeholder, clean deletion
- All packed helper functions (`_getPrizePools`, `_setPrizePools`, `_getPendingPools`, `_setPendingPools`) are `internal` visibility -- modules need them via delegatecall inheritance
- Use existing `revert E()` pattern for all new revert sites (e.g., the hard gate in `_swapTicketSlot`)
- No new named custom errors -- matches codebase convention of single gas-minimal error
- Reuse existing `error E()` declaration already visible to modules

### Claude's Discretion
- Exact NatSpec wording for new fields and helpers (matching existing tone/style)
- Whether to group the new helper functions in a dedicated section or place near related storage vars
- Internal ordering of helper function declarations

### Deferred Ideas (OUT OF SCOPE)
None -- discussion stayed within phase scope

</user_constraints>

<phase_requirements>

## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| STOR-01 | Slot 1 gets `ticketWriteSlot` (uint8), `ticketsFullyProcessed` (bool), `prizePoolFrozen` (bool) at bytes 18-20 | **ACTUAL offsets are 24-26** per `forge inspect`. Slot 1 has `price` (uint128) at offsets 8-23, leaving 8 free bytes at 24-31. The requirement's "bytes 18-20" was based on stale ASCII comments. Intent (pack into Slot 1 padding) is preserved. |
| STOR-02 | `nextPrizePool` + `futurePrizePool` replaced with `prizePoolsPacked` (uint128+uint128) and helpers | `nextPrizePool` at actual Slot 3 (line 308), `futurePrizePool` at actual Slot 16 (line 409). 101 references across 11 files must migrate. Existing packing precedent: `dailyTicketBudgetsPacked` (line 331). |
| STOR-03 | `prizePoolPendingPacked` added with `_getPendingPools()`/`_setPendingPools()` helpers | New uint256 slot. Locked decision: immediately after `prizePoolsPacked`. Follows same uint128+uint128 pattern. |
| STOR-04 | `TICKET_SLOT_BIT` constant, `_tqWriteKey()`, `_tqReadKey()` helpers added | Pure addition -- constant + two `internal view` functions. No storage impact. Key divergence guaranteed by `!=` vs `==` comparison on `ticketWriteSlot`. |

</phase_requirements>

## Critical Finding: Storage Layout Discrepancy

**Confidence: HIGH** -- verified via `forge inspect DegenerusGameStorage storage-layout`

### What the ASCII comments say vs. what the compiler produces

The source code ASCII diagram (lines 34-66) describes two slots:

```
Code comments "SLOT 0":  levelStartTime..jackpotPhaseFlag + 2 bytes padding (30 used)
Code comments "SLOT 1":  jackpotCounter..purchaseStartDay + 14 bytes padding (18 used)
```

But the compiler produces:

```
ACTUAL EVM SLOT 0 (32/32 bytes -- FULLY packed, ZERO padding):
  Offset  Field                            Type     Bytes
  0       levelStartTime                   uint48   6
  6       dailyIdx                         uint48   6
  12      rngRequestTime                   uint48   6
  18      level                            uint24   3
  21      jackpotPhaseFlag                 bool     1
  22      jackpotCounter                   uint8    1      <-- comments say "Slot 1"
  23      earlyBurnPercent                 uint8    1
  24      poolConsolidationDone            bool     1
  25      lastPurchaseDay                  bool     1
  26      decWindowOpen                    bool     1
  27      rngLockedFlag                    bool     1
  28      phaseTransitionActive            bool     1
  29      gameOver                         bool     1
  30      dailyJackpotCoinTicketsPending   bool     1
  31      dailyEthBucketCursor             uint8    1
                                                    = 32 bytes

ACTUAL EVM SLOT 1 (24/32 bytes used -- 8 bytes padding):
  Offset  Field                            Type     Bytes
  0       dailyEthPhase                    uint8    1
  1       compressedJackpotFlag            bool     1
  2       purchaseStartDay                 uint48   6
  8       price                            uint128  16
  24-31   <FREE>                                    8 bytes
```

**Root cause:** The ASCII comments reference two deprecated uint32 fields (`airdropTicketsProcessedCount` and `airdropIndex`) that no longer exist in the code. Without those 8 bytes, the compiler packs everything up to `dailyEthBucketCursor` into Slot 0. The comments were never updated.

### Impact on STOR-01

New field placement must be at Slot 1, offsets 24-26 (NOT 18-20):

| Field | Type | Slot | Offset | Bytes |
|-------|------|------|--------|-------|
| `ticketWriteSlot` | uint8 | 1 | 24 | 1 |
| `ticketsFullyProcessed` | bool | 1 | 25 | 1 |
| `prizePoolFrozen` | bool | 1 | 26 | 1 |
| (remaining padding) | | 1 | 27-31 | 5 |

The user's intent (pack into Slot 1 padding) is fully preserved. Only the byte numbers differ.

### Pool Variable Actual Slots

| Variable | Source Line | Actual Slot | Slot per Comments |
|----------|-----------|-------------|-------------------|
| `currentPrizePool` | 304 | 2 | "Slot 3+" |
| `nextPrizePool` | 308 | 3 | "~5" per CONTEXT |
| `futurePrizePool` | 409 | 16 | "~409" (line, not slot) |

## Standard Stack

### Core
| Tool | Version | Purpose | Why Standard |
|------|---------|---------|--------------|
| Foundry (forge) | latest | Build, test, storage inspection | Already configured in `foundry.toml` |
| Solidity | 0.8.34 | Smart contract language | Locked in `foundry.toml` and pragma |
| forge-std | latest | Test framework (Test.sol) | Used by all existing fuzz tests |

### Key Commands
```bash
# Build (success criteria #4)
forge clean && forge build

# Storage layout verification (THE critical tool for this phase)
forge inspect DegenerusGameStorage storage-layout

# Run targeted tests
forge test --match-path "test/fuzz/StorageFoundation.t.sol" -vvv

# Full test suite
forge test
```

## Architecture Patterns

### Current File Structure
```
contracts/storage/DegenerusGameStorage.sol (~1100 lines)
  +-- Constants section           (lines 118-170)
  +-- Slot 0 variables            (lines 171-211)  timing, FSM
  +-- Slot 1 variables            (lines 213-295)  cursors, flags, price
  +-- Slots 2+ full-width         (lines 297-410)  pools, RNG, mappings
  +-- Ticket Queue helpers/events (lines 454-650)
  +-- Lootbox State               (lines 636-700+)
  +-- ... more sections           through line ~1100
```

### Pattern 1: Packed Slot Field Addition
**What:** Append new small-type fields into free padding at end of a packed slot
**When to use:** Adding uint8/bool to a slot with available padding
**Critical rule:** ALWAYS append AFTER existing fields. Never insert between.
```solidity
// After price (uint128 at offset 8, ending at offset 24):
uint8 internal ticketWriteSlot;        // offset 24
bool internal ticketsFullyProcessed;   // offset 25
bool internal prizePoolFrozen;         // offset 26
```

### Pattern 2: In-Place Variable Replacement (uint256 -> uint256)
**What:** Replace a named uint256 with a different-named uint256 at the same declaration position
**When to use:** When the new variable should occupy the exact same slot
**Critical rule:** Declaration ORDER determines slot assignment. Replace at the EXACT source line.
```solidity
// Line 308: was `uint256 internal nextPrizePool;`
uint256 internal prizePoolsPacked;  // Same slot (3) because same position
```

### Pattern 3: uint128+uint128 Packing with Helpers
**What:** Two uint128 values in one uint256, with getter/setter
**Precedent:** `dailyTicketBudgetsPacked` (line 331) uses similar multi-field packing
```solidity
// Source: audit/PLAN-ALWAYS-OPEN-PURCHASES.md
function _setPrizePools(uint128 next, uint128 future) internal {
    prizePoolsPacked = uint256(future) << 128 | uint256(next);
}
function _getPrizePools() internal view returns (uint128 next, uint128 future) {
    uint256 packed = prizePoolsPacked;
    next = uint128(packed);
    future = uint128(packed >> 128);
}
```

### Pattern 4: Bit-Encoded Mapping Keys (Zero New Storage)
**What:** Use a high bit in uint24 key to create virtual namespace in existing mapping
**When to use:** Avoiding new mapping declarations while supporting double-buffer
```solidity
uint24 internal constant TICKET_SLOT_BIT = 1 << 23; // 0x800000
function _tqWriteKey(uint24 level) internal view returns (uint24) {
    return ticketWriteSlot != 0 ? level | TICKET_SLOT_BIT : level;
}
function _tqReadKey(uint24 level) internal view returns (uint24) {
    return ticketWriteSlot == 0 ? level | TICKET_SLOT_BIT : level;
}
```

### Pattern 5: NatSpec Documentation Style
**What:** 4-5 line NatSpec per variable with @dev, purpose, SECURITY notes
```solidity
// Existing example from the codebase:
/// @dev True when daily RNG is locked (jackpot resolution in progress).
///      Set when daily VRF is requested, cleared when daily processing completes.
///      Mid-day lootbox RNG does NOT set this flag.
///      Used to block burns/opens during jackpot resolution window.
bool internal rngLockedFlag;
```

### Pattern 6: Error Convention
**What:** `error E()` declared per contract; all reverts use `revert E()`
**Note:** `error E()` is NOT declared in `DegenerusGameStorage.sol`. It exists in DegenerusGame.sol and each module independently. Storage helpers needing revert (like `_swapTicketSlot`) require adding `error E();` to DegenerusGameStorage.

### Anti-Patterns to Avoid
- **Trusting ASCII comments over `forge inspect`:** Comments are WRONG about slot boundaries
- **Inserting variables between existing declarations:** Shifts ALL subsequent slots
- **Removing a variable without replacement:** Shifts subsequent slots (catastrophic for delegatecall)
- **Reading packed uint256 as if it were a single value:** After replacing `nextPrizePool` with `prizePoolsPacked`, any unmigrated direct read gets corrupted data

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Storage layout verification | Manual byte counting from source | `forge inspect DegenerusGameStorage storage-layout` | Compiler is the source of truth; existing ASCII comments prove human counting is unreliable |
| uint128 pack/unpack | Inline bit math at every call site | `_getPrizePools()`/`_setPrizePools()` helpers | Single point of truth, testable, matches plan |
| Double-buffer key computation | Inline ternary per call site | `_tqWriteKey()`/`_tqReadKey()` | Consistency, single point of change |

## Common Pitfalls

### Pitfall 1: ASCII Diagram Slot Numbers Are WRONG (CRITICAL)
**What goes wrong:** Planning field placement based on comments (bytes 18-20 of "Slot 1") would collide with `price` at offsets 8-23.
**Why it happens:** Two deprecated uint32 fields were removed from code but comments were never updated, shifting the real slot boundaries.
**How to avoid:** ALWAYS use `forge inspect` output. New fields go at Slot 1 offset 24 (after price).
**Warning signs:** `forge inspect` shows fields at unexpected offsets.

### Pitfall 2: futurePrizePool Removal Shifts Slots 17+ (CRITICAL)
**What goes wrong:** `futurePrizePool` at actual Slot 16. Removing its declaration without replacement shifts `ticketQueue` (Slot 17), `ticketsOwedPacked` (Slot 18), `ticketCursor` (Slot 19), and ALL 90+ subsequent slots.
**Why it happens:** EVM assigns slots sequentially by declaration order.
**How to avoid:** Replace `futurePrizePool` with a same-sized placeholder OR move another uint256 into its exact position. Simply deleting the line is the single most dangerous operation possible.
**Warning signs:** `forge inspect` shows slot numbers changed for variables after the deletion point.

### Pitfall 3: 101 References Break on Variable Rename/Removal
**What goes wrong:** Replacing `nextPrizePool` declaration with `prizePoolsPacked` and removing `futurePrizePool` causes 101 compile errors across 11 files.
**Why it happens:** All modules reference the old variable names directly.
**How to avoid:** Either (a) migrate all 101 references in the same phase, (b) keep old vars alongside new ones temporarily, or (c) add compatibility shims.
**Warning signs:** `forge build` fails with "Undeclared identifier" errors.

### Pitfall 4: error E() Not Declared in Storage
**What goes wrong:** `_swapTicketSlot` needs `revert E()` but DegenerusGameStorage has no `error E()` declaration.
**Why it happens:** Storage contract has no existing revert sites; error is declared in each module independently.
**How to avoid:** Add `error E();` to DegenerusGameStorage. Solidity allows duplicate error declarations with same signature in derived contracts.
**Warning signs:** Compile error "Undeclared identifier" on `E`.

### Pitfall 5: Conflicting Locked Decisions on prizePoolPendingPacked Placement
**What goes wrong:** Locked decision says "immediately after `prizePoolsPacked`" (which would be Slot 4, after Slot 3). But if `futurePrizePool` at Slot 16 is "removed entirely," something must fill Slot 16 to prevent slot shift. Using `prizePoolPendingPacked` at Slot 16 would preserve layout but violates the "immediately after" constraint.
**Why it happens:** The locked decisions were made with incorrect slot numbers in mind.
**How to avoid:** The planner must choose: either (a) place `prizePoolPendingPacked` immediately after `prizePoolsPacked` AND use a `_deprecated_futurePrizePool` placeholder at line 409, or (b) place `prizePoolPendingPacked` at line 409 where `futurePrizePool` was.
**Recommendation:** Option (a) -- keep a placeholder at Slot 16 for safety.

### Pitfall 6: Packed Value Semantic Mismatch
**What goes wrong:** `prizePoolsPacked` stores two uint128 values. Any unmigrated code that reads `prizePoolsPacked` as if it were a single uint256 value (like old `nextPrizePool` was) silently gets wrong data.
**Why it happens:** Variable occupies same slot, same type (uint256), but different semantics.
**How to avoid:** Migrate ALL references before any runtime use. No partial migration.
**Warning signs:** Tests pass at compile time but fail at runtime with wrong pool values.

## Code Examples

### New Slot 1 Fields (verified placement)
```solidity
// Source: Plan document + forge inspect verification
// Place after `price` in source, before Slot 2 section header

/// @dev Active write buffer index for ticket queue double-buffering (0 or 1).
///      Toggled via XOR (`ticketWriteSlot ^= 1`) during queue slot swaps.
///      Write path uses this value; read path uses the opposite.
///
///      SECURITY: uint8 (not bool) required for XOR toggle arithmetic.
///      Only values 0 and 1 are valid; _swapTicketSlot enforces this.
uint8 internal ticketWriteSlot;

/// @dev True when the read slot has been fully drained (all tickets processed).
///      Gate for RNG requests and jackpot logic in advanceGame daily path.
///
///      SECURITY: Must be set to true before any jackpot/phase logic executes.
///      Reset to false on every queue slot swap.
bool internal ticketsFullyProcessed;

/// @dev True when purchase revenue redirects to pending accumulators.
///      Set at daily RNG request time; cleared by _unfreezePool().
///
///      SECURITY: Persists across jackpot phase days. All 5 jackpot payouts
///      use pre-freeze pool values. _unfreezePool is the single control point.
bool internal prizePoolFrozen;
```

### TICKET_SLOT_BIT Constant and Key Helpers
```solidity
// Source: audit/PLAN-ALWAYS-OPEN-PURCHASES.md section 1
// Place in CONSTANTS section

/// @dev Bit mask for double-buffer ticket queue key encoding.
///      Setting bit 23 of a uint24 level key creates a separate namespace
///      within the existing ticketQueue and ticketsOwedPacked mappings.
///      Max real level: 2^23 - 1 = 8,388,607 (game would take millennia).
uint24 internal constant TICKET_SLOT_BIT = 1 << 23;

function _tqWriteKey(uint24 level) internal view returns (uint24) {
    return ticketWriteSlot != 0 ? level | TICKET_SLOT_BIT : level;
}

function _tqReadKey(uint24 level) internal view returns (uint24) {
    return ticketWriteSlot == 0 ? level | TICKET_SLOT_BIT : level;
}
```

### Packed Prize Pool Helpers
```solidity
// Source: audit/PLAN-ALWAYS-OPEN-PURCHASES.md section 1

/// @dev Packed live prize pools: [128:256] futurePrizePool | [0:128] nextPrizePool.
///      uint128 max ~ 3.4e20 ETH -- far exceeds total ETH supply.
///      Saves 1 SSTORE per purchase (both written together).
uint256 internal prizePoolsPacked;

/// @dev Packed pending accumulators during prize pool freeze.
///      [128:256] futurePrizePoolPending | [0:128] nextPrizePoolPending.
///      Zeroed at freeze start; applied to live pools at unfreeze.
uint256 internal prizePoolPendingPacked;

function _setPrizePools(uint128 next, uint128 future) internal {
    prizePoolsPacked = uint256(future) << 128 | uint256(next);
}
function _getPrizePools() internal view returns (uint128 next, uint128 future) {
    uint256 packed = prizePoolsPacked;
    next = uint128(packed);
    future = uint128(packed >> 128);
}

function _setPendingPools(uint128 next, uint128 future) internal {
    prizePoolPendingPacked = uint256(future) << 128 | uint256(next);
}
function _getPendingPools() internal view returns (uint128 next, uint128 future) {
    uint256 packed = prizePoolPendingPacked;
    next = uint128(packed);
    future = uint128(packed >> 128);
}
```

### Swap/Freeze/Unfreeze Helpers
```solidity
// Source: audit/PLAN-ALWAYS-OPEN-PURCHASES.md sections 1-3

function _swapTicketSlot(uint24 purchaseLevel) internal {
    uint24 rk = _tqReadKey(purchaseLevel);
    if (ticketQueue[rk].length != 0) revert E();
    ticketWriteSlot ^= 1;
    ticketsFullyProcessed = false;
}

function _swapAndFreeze(uint24 purchaseLevel) internal {
    _swapTicketSlot(purchaseLevel);
    if (!prizePoolFrozen) {
        prizePoolFrozen = true;
        prizePoolPendingPacked = 0;
    }
}

function _unfreezePool() internal {
    if (!prizePoolFrozen) return;
    (uint128 pNext, uint128 pFuture) = _getPendingPools();
    (uint128 next, uint128 future) = _getPrizePools();
    _setPrizePools(next + pNext, future + pFuture);
    prizePoolPendingPacked = 0;
    prizePoolFrozen = false;
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Separate `nextPrizePool` + `futurePrizePool` (2 slots) | Packed `prizePoolsPacked` (1 slot) | This phase | Saves 1 SSTORE per purchase |
| Direct mapping key `ticketQueue[level]` | Double-buffered via `_tqWriteKey(level)` | This phase | Enables concurrent purchase + processing |
| No pending accumulators | `prizePoolPendingPacked` + freeze/unfreeze | This phase | Isolates jackpot payouts from concurrent purchases |

## Open Questions

1. **How to handle futurePrizePool removal without slot shift (CRITICAL)**
   - What we know: `futurePrizePool` at Slot 16. Removing it shifts Slots 17-106 (ticketQueue, ticketsOwedPacked, all 90+ subsequent slots). This is catastrophic.
   - What's unclear: Locked decision says "removed entirely -- no comment placeholder, clean deletion." But clean deletion corrupts the layout.
   - Recommendation: The planner MUST either (a) use `uint256 internal _deprecated_futurePrizePool;` as a placeholder, or (b) move `prizePoolPendingPacked` into that exact declaration position (but this violates the "immediately after prizePoolsPacked" locked decision). Option (a) is safest. Since this is a fresh deploy (non-upgradeable contract), the deprecated slot wastes 32 bytes but costs nothing at runtime.

2. **Should Phase 1 migrate all 101 nextPrizePool/futurePrizePool references?**
   - What we know: Replacing/removing the variable declarations breaks compilation of 11 files.
   - CONTEXT.md line 66 explicitly says: "decision for planner."
   - Options: (A) Keep old vars temporarily, add new packed vars at new slots, migrate in Phase 2. (B) Replace declarations + migrate all 101 references in Phase 1. (C) Replace declarations + add compatibility shims (`function _legacyNextPrizePool() internal view returns (uint256)`) that Phase 2 removes.
   - Recommendation: Option C gives the cleanest path -- locked decisions are honored (variable names change) while compilation is maintained via shims.

3. **error E() declaration location**
   - What we know: Must add `error E();` to DegenerusGameStorage for `_swapTicketSlot` revert.
   - Safe because Solidity allows identical error declarations in base and derived contracts.
   - Recommendation: Add it in the Constants section, before Slot 0 variables.

4. **ASCII diagram correction scope**
   - What we know: Both Slot 0 and Slot 1 diagrams have wrong byte offsets and slot boundaries.
   - Recommendation: Rewrite completely to match `forge inspect` reality. This is low effort and required by locked decision to update both diagrams.

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Foundry forge-std (Test.sol), Solidity 0.8.34, via_ir=true |
| Config file | `foundry.toml` (test = "test/fuzz" by default) |
| Quick run command | `forge test --match-path "test/fuzz/StorageFoundation.t.sol" -vvv` |
| Full suite command | `forge test` |

### Phase Requirements to Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| STOR-01 | New fields at correct Slot 1 offsets (24, 25, 26) | smoke | `forge inspect DegenerusGameStorage storage-layout` (verify in test) | No -- Wave 0 |
| STOR-02 | `_getPrizePools`/`_setPrizePools` round-trip correctly for boundary values | unit | `forge test --match-test "testPrizePoolPacking" -vvv` | No -- Wave 0 |
| STOR-03 | `_getPendingPools`/`_setPendingPools` round-trip correctly | unit | `forge test --match-test "testPendingPoolPacking" -vvv` | No -- Wave 0 |
| STOR-04 | `_tqWriteKey != _tqReadKey` for same input, both `ticketWriteSlot` values | unit | `forge test --match-test "testTicketSlotKeys" -vvv` | No -- Wave 0 |
| ALL | `forge clean && forge build` zero warnings | smoke | `forge clean && forge build 2>&1` | N/A (CLI) |

### Sampling Rate
- **Per task commit:** `forge clean && forge build` (compilation check)
- **Per wave merge:** `forge test` (full suite including new tests)
- **Phase gate:** `forge inspect` layout verification + all new unit tests green + full `forge test` green

### Wave 0 Gaps
- [ ] `test/fuzz/StorageFoundation.t.sol` -- new test file covering STOR-01 through STOR-04
- [ ] Test harness contract inheriting DegenerusGameStorage, exposing internal functions as public for testing
- [ ] `error E();` declaration in DegenerusGameStorage (needed for `_swapTicketSlot`)
- Framework install: no gaps (forge-std already in `lib/`)

## Sources

### Primary (HIGH confidence)
- `forge inspect DegenerusGameStorage storage-layout` -- actual compiled EVM slot assignments, verified 2026-03-11
- `contracts/storage/DegenerusGameStorage.sol` -- full source (~1100 lines), all relevant sections read
- `audit/PLAN-ALWAYS-OPEN-PURCHASES.md` -- complete plan with Solidity snippets for all helpers (536 lines)
- `foundry.toml` -- build config (solc 0.8.34, via_ir=true, optimizer_runs=2)

### Secondary (MEDIUM confidence)
- `test/fuzz/DeployCanary.t.sol` + `test/fuzz/helpers/DeployProtocol.sol` -- test infrastructure patterns
- `.planning/phases/01-storage-foundation/01-CONTEXT.md` -- locked decisions from user discussion

### Tertiary (LOW confidence)
- None -- all findings verified from source code and compiler output

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH -- directly from `foundry.toml` and existing project config
- Architecture: HIGH -- storage layout verified via `forge inspect` compiler output; all patterns from existing code
- Pitfalls: HIGH -- critical ASCII discrepancy discovered via direct compiler verification; reference counts from grep
- Open questions: MEDIUM -- slot conflict between locked decisions needs planner resolution

**Research date:** 2026-03-11
**Valid until:** 2026-04-11 (stable domain; Solidity storage layout rules don't change between patch versions)
