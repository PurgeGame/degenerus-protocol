# Phase 1: Storage Foundation - Research

**Researched:** 2026-03-11
**Domain:** Solidity storage layout engineering, EVM slot packing, delegatecall-safe storage patterns
**Confidence:** HIGH

## Summary

Phase 1 adds three new state variables to the packed slot, two packed uint256 pool slots with helper functions, a constant, and two key-encoding helpers to `DegenerusGameStorage.sol`. The primary risk is storage slot misalignment breaking all delegatecall modules. A critical finding from this research is that **the ASCII slot diagrams in the source code are wrong about slot boundaries** -- what comments label "Slot 0" and "Slot 1" actually pack entirely into a single EVM Slot 0 (32 bytes). The real Slot 1 starts at `dailyEthPhase` and contains only 24 used bytes with 8 bytes free at the end.

The second major planning concern is that removing `nextPrizePool` and `futurePrizePool` will break 101 references across 11 files. Phase 1 must either (a) keep the old variables and add new packed ones alongside (deferring removal to Phase 2), or (b) do a full find-replace in this phase. Option (a) is recommended because it keeps Phase 1 scoped to Storage only and maintains compilation throughout, but option (b) is what CONTEXT.md line 23-24 specifies ("replaces `nextPrizePool` in-place").

**Primary recommendation:** Add new fields at end of actual Slot 1 (byte offset 24), add packed pool slots and helpers, add key-encoding functions. Run `forge inspect` before and after every change. Handle the old-variable removal carefully per the locked decisions.

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
| STOR-01 | Slot 1 gets `ticketWriteSlot` (uint8), `ticketsFullyProcessed` (bool), `prizePoolFrozen` (bool) at bytes 18-20 | Slot layout analysis shows actual Slot 1 has 8 free bytes starting at offset 24. The "bytes 18-20" in the requirement refers to the COMMENT's Slot 1 numbering. See Critical Pitfall 1 for mapping. |
| STOR-02 | `nextPrizePool` + `futurePrizePool` replaced with `prizePoolsPacked` and helpers | `nextPrizePool` at actual Slot 3, `futurePrizePool` at actual Slot 16. 101 references across 11 files. Existing packing precedent: `dailyTicketBudgetsPacked`. |
| STOR-03 | `prizePoolPendingPacked` added with helpers | New uint256 slot; goes immediately after `prizePoolsPacked` per locked decision. Helper code provided in plan document. |
| STOR-04 | `TICKET_SLOT_BIT` constant, `_tqWriteKey()`, `_tqReadKey()` helpers | Constants have no storage impact. Helper functions are `internal view`, no storage. Code in plan document verified correct: XOR between write/read keys guaranteed by `!=` vs `==` check. |

</phase_requirements>

## Standard Stack

### Core
| Tool | Version | Purpose | Why Standard |
|------|---------|---------|--------------|
| Foundry (forge) | latest | Build, test, storage inspection | Already configured in `foundry.toml` |
| Solidity | 0.8.34 | Smart contract language | Locked in `foundry.toml` and pragma |

### Key Commands
```bash
# Build
forge clean && forge build

# Inspect storage layout (THE critical verification tool for this phase)
forge inspect DegenerusGameStorage storage-layout --json

# Run existing tests
forge test

# Quick targeted test
forge test --match-test testTicketSlotKeys -vvv
```

## Architecture Patterns

### Current Storage Layout (ACTUAL, from forge inspect -- NOT matching code comments)

```
ACTUAL EVM SLOT 0 (32 bytes) -- What comments call "Slot 0" + "Slot 1"
  [0:6]   levelStartTime         uint48
  [6:12]  dailyIdx               uint48
  [12:18] rngRequestTime         uint48
  [18:21] level                  uint24
  [21:22] jackpotPhaseFlag       bool
  [22:23] jackpotCounter         uint8     <-- comments say this starts "Slot 1"
  [23:24] earlyBurnPercent       uint8
  [24:25] poolConsolidationDone  bool
  [25:26] lastPurchaseDay        bool
  [26:27] decWindowOpen          bool
  [27:28] rngLockedFlag          bool
  [28:29] phaseTransitionActive  bool
  [29:30] gameOver               bool
  [30:31] dailyJackpotCoinTicketsPending bool
  [31:32] dailyEthBucketCursor   uint8
  Total: 32 bytes (full, 0 padding)

ACTUAL EVM SLOT 1 (32 bytes) -- What comments partially call "Slot 1 continued"
  [0:1]   dailyEthPhase          uint8
  [1:2]   compressedJackpotFlag  bool
  [2:8]   purchaseStartDay       uint48
  [8:24]  price                  uint128
  [24:32] <padding>              8 bytes FREE  <-- NEW FIELDS GO HERE
  Total: 24 bytes used, 8 bytes free

ACTUAL EVM SLOT 2: currentPrizePool (uint256)
ACTUAL EVM SLOT 3: nextPrizePool (uint256)    <-- becomes prizePoolsPacked
...
ACTUAL EVM SLOT 16: futurePrizePool (uint256) <-- removed
```

### Pattern 1: Packed Slot Field Addition
**What:** Add new small-type fields into free padding at end of an existing packed slot
**When to use:** When adding uint8/bool fields to a slot with available padding
**Critical rule:** New fields MUST go AFTER all existing fields in the slot. Never insert between existing fields.

```solidity
// After price (uint128 at offset 8, ending at offset 24):
// New fields pack at offsets 24, 25, 26
uint8 internal ticketWriteSlot;        // offset 24
bool internal ticketsFullyProcessed;   // offset 25
bool internal prizePoolFrozen;         // offset 26
// 5 bytes padding remaining [27:32]
```

### Pattern 2: In-Place Variable Replacement (uint256 -> uint256)
**What:** Replace a named uint256 variable with a different-named uint256 at the same declaration position
**When to use:** When the new variable occupies exactly the same slot as the old one
**Critical rule:** The declaration order in the source file determines slot assignment. Replace at the EXACT line position.

```solidity
// Line 308: was `uint256 internal nextPrizePool;`
// Now:
uint256 internal prizePoolsPacked;
// This occupies the SAME slot (Slot 3) because declaration order is unchanged.
```

### Pattern 3: Internal View Helper Functions (No Storage Impact)
**What:** `internal view` or `internal pure` functions in the storage contract
**When to use:** For encoding/decoding packed values
**Critical rule:** Functions do NOT occupy storage slots. They can be added anywhere without affecting layout.

### Anti-Patterns to Avoid
- **Inserting variables between existing declarations:** Shifts ALL subsequent slots, catastrophic for delegatecall modules
- **Relying on code comments for slot numbers:** Comments are WRONG (see Critical Pitfall 1). Always verify with `forge inspect`
- **Changing variable types in-place:** e.g. uint256 -> uint128 would change slot packing rules
- **Removing a variable without replacing it:** Shifts all subsequent slots down by one

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Storage layout verification | Manual byte counting | `forge inspect DegenerusGameStorage storage-layout --json` | Compiler is the source of truth; human counting is error-prone, especially given the existing comment errors |
| Slot packing math | Custom offset calculations | Solidity compiler auto-packing + forge inspect verification | Compiler handles alignment rules automatically |
| uint128 packing/unpacking | Inline assembly | Solidity shift/cast (`uint128(packed)`, `uint128(packed >> 128)`) | Compiler generates identical code, Solidity casts are checked |

## Common Pitfalls

### Pitfall 1: ASCII Diagram Slot Numbers Are WRONG (CRITICAL)
**What goes wrong:** The source code comments at lines 34-66 label storage as "Slot 0" and "Slot 1" but the actual EVM layout packs everything from `levelStartTime` through `dailyEthBucketCursor` into a single Slot 0 (32 bytes exactly). What comments call "Slot 1" fields actually START at actual Slot 0 offset 22.
**Why it happens:** The original author mentally separated the fields into logical groups but the EVM packer fits all 32 bytes into one slot.
**How to avoid:** ALWAYS use `forge inspect` output as ground truth. The requirement says "bytes 18-20 of Slot 1" -- this maps to actual Slot 1 offsets 24-26 (after `price` at offset 8-24). The new fields go at the END of actual Slot 1, not at "byte 18".
**Warning signs:** If `forge inspect` shows new fields at unexpected offsets or in unexpected slots.
**Resolution:** When updating the ASCII diagrams, fix them to reflect ACTUAL slot boundaries, or at minimum make the new field placement match what `forge inspect` produces.

### Pitfall 2: Removing nextPrizePool/futurePrizePool Breaks 101 References
**What goes wrong:** Deleting the old variable declarations causes compile errors in 11 files across 101 call sites.
**Why it happens:** The locked decision says "replaces `nextPrizePool` in-place" and "removed entirely" for `futurePrizePool`.
**How to avoid:** The planner must decide: either (a) replace declarations AND do a full migration of all 101 references to use packed helpers in the same phase (large scope expansion), or (b) keep old vars temporarily and add packed vars alongside (deferred migration). The locked decision implies (a). If taking approach (a), this phase becomes much larger than "only Storage" -- it touches all 11 files.
**Recommendation:** Replace declarations as locked, but also create temporary compatibility shims in the storage file itself:
```solidity
// Temporary compatibility -- removed in Phase 2
function _setNextPrizePool(uint256 val) internal {
    (uint128 _, uint128 future) = _getPrizePools();
    _setPrizePools(uint128(val), future);
}
// ... etc
```
This keeps compilation working while the real migration happens in Phase 2. OR: scope the full 101-reference migration into Phase 1. The planner must decide.

### Pitfall 3: futurePrizePool Removal Shifts Slots 17+
**What goes wrong:** `futurePrizePool` is at actual Slot 16. Removing its declaration without replacement would shift `ticketQueue` (Slot 17), `ticketsOwedPacked` (Slot 18), and ALL subsequent slots, destroying the storage layout.
**Why it happens:** EVM assigns slots sequentially based on declaration order.
**How to avoid:** Replace `futurePrizePool` with a placeholder `uint256 internal _deprecated_futurePrizePool;` OR move `prizePoolPendingPacked` into its position. The locked decision says "removed entirely" which is dangerous. The planner must address this: either use a deprecated placeholder or move another uint256 into its exact position.
**This is the single most dangerous operation in Phase 1.**

### Pitfall 4: prizePoolsPacked Replacing nextPrizePool Changes Semantics
**What goes wrong:** `prizePoolsPacked` stores TWO uint128 values (next + future) in one uint256. But `nextPrizePool` stored a single uint256 value. Any code that reads `nextPrizePool` directly will now read `prizePoolsPacked` which has a completely different bit layout.
**How to avoid:** ALL 101 references must be migrated to use `_getPrizePools()`/`_setPrizePools()` helpers BEFORE the contract is used. If any reference is missed, it silently reads/writes corrupted data.
**Warning signs:** `forge build` succeeds but runtime behavior is wrong (if old code assigns to `prizePoolsPacked` treating it as a single value).

### Pitfall 5: error E() Not Declared in Storage Contract
**What goes wrong:** The `error E()` declaration exists in DegenerusGame.sol and each module, but NOT in DegenerusGameStorage.sol. Any new revert in Storage needs the error visible.
**Why it happens:** Storage contract doesn't currently have any revert sites.
**How to avoid:** Add `error E();` declaration to DegenerusGameStorage.sol. Since all modules also declare it, and Solidity allows duplicate custom error declarations with the same signature, this is safe.

### Pitfall 6: _swapTicketSlot and _swapAndFreeze Scope Question
**What goes wrong:** CONTEXT.md lists these as Phase 1 functions but they are swap/freeze OPERATIONS that belong to Phase 2 (Queue) and Phase 3 (Freeze) respectively.
**How to avoid:** The CONTEXT.md `<domain>` section says "swap/freeze/unfreeze functions to DegenerusGameStorage.sol. This phase delivers the foundation that all subsequent phases build on." So these ARE in scope for Phase 1 as storage-level helpers. The planner should include them.

## Code Examples

### New Slot 1 Fields (verified placement after price at actual offset 24)
```solidity
// Source: forge inspect output + plan document
// After purchaseStartDay and price in actual Slot 1:

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

### Packed Prize Pool Helpers (from plan document, verified correct)
```solidity
// Source: audit/PLAN-ALWAYS-OPEN-PURCHASES.md section 1

/// @dev Packed live prize pools: [128:256] futurePrizePool | [0:128] nextPrizePool
uint256 internal prizePoolsPacked;

function _setPrizePools(uint128 next, uint128 future) internal {
    prizePoolsPacked = uint256(future) << 128 | uint256(next);
}

function _getPrizePools() internal view returns (uint128 next, uint128 future) {
    uint256 packed = prizePoolsPacked;
    next = uint128(packed);
    future = uint128(packed >> 128);
}
```

### Key Encoding Helpers (from plan document, verified correct)
```solidity
// Source: audit/PLAN-ALWAYS-OPEN-PURCHASES.md section 1

uint24 internal constant TICKET_SLOT_BIT = 1 << 23; // 0x800000

function _tqWriteKey(uint24 level) internal view returns (uint24) {
    return ticketWriteSlot != 0 ? level | TICKET_SLOT_BIT : level;
}

function _tqReadKey(uint24 level) internal view returns (uint24) {
    return ticketWriteSlot == 0 ? level | TICKET_SLOT_BIT : level;
}
```

### Existing Packing Precedent in Codebase
```solidity
// Source: DegenerusGameStorage.sol line 331
// dailyTicketBudgetsPacked uses the same uint256 packed pattern:
// [counterStep (8 bits @ 0)] [dailyTicketUnits (64 bits @ 8)] ...
uint256 internal dailyTicketBudgetsPacked;
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Separate `nextPrizePool` + `futurePrizePool` (2 slots) | Packed `prizePoolsPacked` (1 slot) | This phase | Saves 1 SSTORE per purchase; 1 SLOAD on reads |
| Direct mapping key `ticketQueue[level]` | Double-buffered `ticketQueue[_tqWriteKey(level)]` | This phase | Enables concurrent purchase + processing |
| No pending accumulators | `prizePoolPendingPacked` with freeze/unfreeze | This phase | Enables prize pool isolation during processing |

## Open Questions

1. **How to handle futurePrizePool removal without slot shift**
   - What we know: `futurePrizePool` is at actual Slot 16. Removing it shifts Slots 17+ (ticketQueue, ticketsOwedPacked, etc.)
   - What's unclear: The locked decision says "removed entirely -- no comment placeholder, clean deletion" but this would corrupt the storage layout
   - Recommendation: The planner MUST either (a) replace with `uint256 internal _deprecated_futurePrizePool;` placeholder or (b) move `prizePoolPendingPacked` into that exact declaration position. Option (b) is cleanest: `prizePoolPendingPacked` takes the slot that `futurePrizePool` occupied. BUT the locked decision also says `prizePoolPendingPacked` goes "immediately after `prizePoolsPacked`" which would be Slot 4 (after Slot 3 nextPrizePool replacement). These two constraints conflict. The planner must resolve this.

2. **Should Phase 1 migrate all 101 nextPrizePool/futurePrizePool references?**
   - What we know: Locked decision says "replaces in-place" and "removed entirely". This means compile will break unless all references migrate.
   - What's unclear: CONTEXT.md line 66 says "decision for planner" on whether to do full find-replace in this phase
   - Recommendation: Add temporary compatibility getters/setters OR include a wave in Phase 1 for migrating all 101 references. The planner should decide based on phase scope goals.

3. **ASCII diagram correction scope**
   - What we know: Existing diagrams are wrong about slot boundaries. Locked decision says update both diagrams.
   - What's unclear: Should we fix the existing incorrect slot numbering or only add new fields with correct numbering?
   - Recommendation: Fix the entire diagram to match reality. The effort is small and prevents future confusion.

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Foundry (forge test) via Solidity 0.8.34, via_ir=true |
| Config file | `foundry.toml` (exists) |
| Quick run command | `forge test --match-test testTicketSlotKeys -vvv` |
| Full suite command | `forge test` |

### Phase Requirements -> Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| STOR-01 | New fields at correct slot/offset | smoke (forge inspect) | `forge inspect DegenerusGameStorage storage-layout --json \| python3 -c "..."` | No -- Wave 0 |
| STOR-02 | prizePoolsPacked replaces nextPrizePool; helpers compile and round-trip | unit | `forge test --match-test testPrizePoolPacking -vvv` | No -- Wave 0 |
| STOR-03 | prizePoolPendingPacked helpers compile and round-trip | unit | `forge test --match-test testPendingPoolPacking -vvv` | No -- Wave 0 |
| STOR-04 | _tqWriteKey and _tqReadKey produce different keys for same input; invariant holds for both ticketWriteSlot values | unit | `forge test --match-test testTicketSlotKeys -vvv` | No -- Wave 0 |

### Sampling Rate
- **Per task commit:** `forge clean && forge build` (zero warnings check)
- **Per wave merge:** `forge test` (full suite)
- **Phase gate:** `forge inspect` verification + all new unit tests green + `forge clean && forge build` zero warnings

### Wave 0 Gaps
- [ ] `test/unit/StorageFoundation.t.sol` -- new test file for STOR-01 through STOR-04
  - Test: `testSlot1FieldOffsets` -- verify `ticketWriteSlot`, `ticketsFullyProcessed`, `prizePoolFrozen` at expected offsets via forge inspect or assembly `sload`
  - Test: `testPrizePoolPackingRoundTrip` -- set/get for prizePoolsPacked with boundary values (0, max uint128, mixed)
  - Test: `testPendingPoolPackingRoundTrip` -- same for prizePoolPendingPacked
  - Test: `testTicketSlotKeys` -- for ticketWriteSlot=0 and ticketWriteSlot=1, assert `_tqWriteKey(level) != _tqReadKey(level)` for multiple level values
  - Test: `testTicketSlotKeyBit23Isolation` -- verify bit 23 is set on one and not the other
- [ ] Test harness: a minimal contract that inherits `DegenerusGameStorage` and exposes internal functions for testing (since they are `internal`)
- [ ] Framework install: already configured -- no gaps

## Sources

### Primary (HIGH confidence)
- `forge inspect DegenerusGameStorage storage-layout --json` -- actual EVM slot assignments (compiler output, ground truth)
- `contracts/storage/DegenerusGameStorage.sol` -- 1416 lines, full source read
- `audit/PLAN-ALWAYS-OPEN-PURCHASES.md` -- plan document with exact Solidity snippets for all helpers
- `foundry.toml` -- build configuration (Solidity 0.8.34, via_ir=true, optimizer_runs=2)

### Secondary (MEDIUM confidence)
- `.planning/phases/01-storage-foundation/01-CONTEXT.md` -- locked decisions from user discussion

### Tertiary (LOW confidence)
- None -- all findings verified from source code and compiler output

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH -- directly from `foundry.toml` and existing project config
- Architecture: HIGH -- storage layout verified via `forge inspect` compiler output
- Pitfalls: HIGH -- discovered via actual compiler output contradicting source comments (Pitfall 1), and by counting actual references (Pitfall 2-4)
- Open questions: MEDIUM -- slot conflict between locked decisions needs planner resolution

**Research date:** 2026-03-11
**Valid until:** 2026-04-11 (stable domain; Solidity storage layout rules don't change between patch versions)
