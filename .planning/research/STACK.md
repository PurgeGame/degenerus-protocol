# Stack Research

**Domain:** Solidity smart contract — double-buffered ticket queues, packed prize pool storage, prize pool freeze/unfreeze mechanics
**Researched:** 2026-03-11
**Confidence:** HIGH

---

## Context: What This Milestone Adds

This milestone adds infrastructure to existing Degenerus Protocol contracts. No new external
dependencies are introduced. The relevant stack question is: which Solidity patterns, EVM
mechanics, and existing in-repo utilities should govern the implementation?

---

## Core Technologies

| Technology | Version | Purpose | Why Recommended |
|------------|---------|---------|-----------------|
| Solidity | 0.8.34 | Contract language | Locked per project; auto-overflow checks, custom errors, named return variables |
| Foundry (forge) | 1.5.1-stable | Build + fuzz testing | Already in use; `--via-ir` pipeline active; fuzz suite covers invariants |
| Hardhat + ethers | 2.28.3 + toolbox | Unit/integration tests | Already in use for JS test suite; no changes needed |
| OpenZeppelin Contracts | 5.4.0 | Reference only | Already installed; no new OZ primitives needed for this milestone |

---

## Recommended Stack Patterns (No New Dependencies)

### 1. uint128 Packing via Raw Bitwise Operations

**Pattern:** Two `uint128` values packed into one `uint256` storage slot using shift and mask.

```solidity
// Pack: future in high 128 bits, next in low 128 bits
uint256 internal prizePoolsPacked;

function _setPrizePools(uint128 next, uint128 future) internal {
    prizePoolsPacked = uint256(future) << 128 | uint256(next);
}

function _getPrizePools() internal view returns (uint128 next, uint128 future) {
    uint256 packed = prizePoolsPacked;
    next   = uint128(packed);
    future = uint128(packed >> 128);
}
```

**Why this approach:**
- Zero new imports. Raw bit operations on `uint256` are the canonical EVM pattern.
- `uint128` truncation cast is safe: `uint128(x)` discards the high 128 bits exactly.
- `uint256(future) << 128` must widen before shifting — `uint128 << 128` would be a type
  error; widening to `uint256` first is required and is the only correct form.
- Packing both pools into a single slot collapses every "touch both pools" operation from
  2 SLOADs + 2 SSTOREs to 1 SLOAD + 1 SSTORE (saves ~5,000 gas per purchase call, more
  in `consolidatePrizePools` and `payDailyJackpot` which currently do 3+ mutations).

**No library needed:** OpenZeppelin's `StorageSlot` operates on slot pointers, not
sub-slot packing. Solady's `LibPack` packs smaller types but adds an import. Neither
offers anything the inline bit ops don't already do for exactly two `uint128` values.

**Confidence:** HIGH — established EVM pattern, verified against existing `dailyTicketBudgetsPacked`
usage in the same file (line 331), which uses identical shift/mask technique.

---

### 2. Bit-23 Key Encoding for Double-Buffer Queue

**Pattern:** Repurpose the unused high bit of the existing `uint24` mapping key rather than
adding a new mapping declaration.

```solidity
uint24 internal constant TICKET_SLOT_BIT = 1 << 23; // 0x800000

function _tqWriteKey(uint24 level) internal view returns (uint24) {
    return ticketWriteSlot != 0 ? level | TICKET_SLOT_BIT : level;
}

function _tqReadKey(uint24 level) internal view returns (uint24) {
    return ticketWriteSlot == 0 ? level | TICKET_SLOT_BIT : level;
}
```

**Why this approach:**
- `ticketQueue` and `ticketsOwedPacked` mapping types are `mapping(uint24 => ...)`.
  The key space is 2^24 = 16,777,216 entries. Max real level that game can reach before
  entropy death is approximately 8,388,607 (2^23 - 1) — well within the lower half of
  the key space. Bit 23 is structurally free.
- Avoids declaring a second parallel mapping. A second mapping would require a new storage
  slot, new slot comments, and double the delegatecall surface for slot alignment bugs.
- The constant `TICKET_SLOT_BIT` is a pure compile-time value — zero runtime cost.
- The read/write key helpers are `internal view` — inlined by the optimizer (`via_ir = true`
  in `foundry.toml`; IR pipeline aggressively inlines small view functions).

**Key correctness invariant:** `_tqReadKey` returns `level | TICKET_SLOT_BIT` when
`ticketWriteSlot == 0` (i.e., write is on slot 0, read is on slot 1 = the bit-set key).
When `ticketWriteSlot == 1`, read is slot 0 = raw level. Write key is always the inverse.

**Confidence:** HIGH — same technique as the existing `BitPackingLib.setPacked` which
already uses masks and shifts for the `mintPacked_` mapping. The `uint24` key space
analysis is arithmetic, not opinion.

---

### 3. Slot 1 Packing: 3 New Booleans/uint8 in Existing 14-Byte Padding

**Pattern:** Append new state variables after `purchaseStartDay` to consume 3 bytes of the
confirmed 14-byte padding in Slot 1.

```
| [12:18] purchaseStartDay         uint48   (existing)              |
| [18:19] ticketWriteSlot          uint8    write buffer index (0/1)|
| [19:20] ticketsFullyProcessed    bool     read slot drained flag  |
| [20:21] prizePoolFrozen          bool     pool freeze active flag |
| [21:32] <padding>                         11 bytes remaining      |
```

**Why uint8 for ticketWriteSlot instead of bool:**
- The swap uses XOR: `ticketWriteSlot ^= 1`. XOR on a `bool` is not idiomatic Solidity
  and emits a wider opcode sequence. XOR on `uint8` is natural and the optimizer produces
  a single `XOR` EVM instruction.
- The value semantics are binary (0 or 1), but the mutation operation is numeric.

**Storage alignment verification:**
- Slot 1 currently uses 18 bytes (verified from storage layout comment at line 64 of
  `DegenerusGameStorage.sol`). Adding 3 bytes brings it to 21 bytes, leaving 11 bytes
  of padding. No slot boundary is crossed.
- `prizePoolsPacked` (new, replaces `nextPrizePool` + `futurePrizePool`) and
  `prizePoolPendingPacked` (new) each occupy their own full 32-byte slot in the Slots 3+
  region. Fresh deploy assumed; slot renumbering is acceptable per PROJECT.md.

**Confidence:** HIGH — derived directly from the storage layout header in
`DegenerusGameStorage.sol` lines 48–65.

---

### 4. `unchecked` Arithmetic for uint128 Local Accumulation

**Pattern:** Use `unchecked` blocks when accumulating into `uint128` locals loaded from
packed storage, where overflow is provably impossible.

```solidity
(uint128 next, uint128 future) = _getPrizePools();
unchecked {
    next   += uint128(nextShare);   // nextShare always < total ETH supply
    future += uint128(futureShare); // futureShare always < total ETH supply
}
_setPrizePools(next, future);
```

**Why:**
- Total ETH supply is ~120M ETH = ~1.2e26 wei. `uint128` max is ~3.4e38 wei. Overflow
  requires accumulating 2.8e12 ETH — physically impossible.
- Solidity 0.8's default overflow check on `uint128` addition costs ~3 extra gas per
  operation (a comparison + conditional revert). With `unchecked`, this is eliminated.
- The existing codebase uses `unchecked` in exactly this pattern (see `_queueTickets`,
  line 511 of `DegenerusGameStorage.sol`). Consistent style.

**Caution:** Only use `unchecked` for additions to prize pool values — NOT for subtractions
(jackpot payouts must retain overflow protection to catch accounting bugs).

**Confidence:** HIGH — mathematical argument, consistent with existing project style.

---

### 5. Custom Errors for New Revert Paths

**Pattern:** Use custom errors (Solidity 0.8.4+) for the two new revert cases.

```solidity
error ReadSlotNotDrained();
// (rngLockedFlag reverts that are removed need no replacement — they simply go away)
```

**Why:**
- Custom errors cost ~50 gas less than `revert("string")` and are already used throughout
  the codebase (e.g., `revert E()`, `revert RngLocked()` seen in the grep output).
- `ReadSlotNotDrained()` is the only new revert path introduced by this milestone.
  It fires only in the hard-gate check inside `_swapTicketSlot()`.

**Confidence:** HIGH — project already uses custom errors exclusively.

---

### 6. `via_ir = true` and Its Effect on This Milestone

**Implication:** The Foundry config has `via_ir = true` with `optimizer_runs = 2`. The IR
pipeline inlines aggressively and handles stack pressure from deep local variable usage.

**Relevance to this milestone:**
- Functions like `_unfreezePool()` use 4 local `uint128` variables simultaneously.
  Without `via_ir`, this could hit the 16-variable stack limit in complex surrounding
  contexts. With `via_ir`, the optimizer handles stack allocation via SSA form.
- The load-once/store-once pattern for prize pools (load into locals, mutate locals, store)
  is exactly what `via_ir` optimizes best — it can merge the final SSTORE across branches.
- **No action needed:** `via_ir = true` is already set. Do not disable it.

**Confidence:** HIGH — `foundry.toml` confirmed, Solidity IR docs are stable.

---

## Supporting Libraries

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| forge-std | (git submodule) | Foundry test utilities (vm.warp, vm.prank, assertions) | All Foundry tests; already in use |
| BitPackingLib (internal) | — | setPacked helper for mintPacked_ word | Already used for mint data; pattern reference only — do NOT extend it for prize pool packing (different access pattern) |

---

## Development Tools

| Tool | Purpose | Notes |
|------|---------|-------|
| `forge test --match-path 'test/fuzz/*' -vv` | Fuzz + invariant tests | Run after each storage change; catches slot corruption immediately |
| `forge inspect <Contract> storage` | Print storage layout | Verify Slot 1 packing is correct after adding new fields |
| `forge snapshot` | Gas snapshot | Baseline before / after packed pools to confirm SSTORE reduction |
| `slither` | Static analysis | `npm run slither`; catches unchecked-send, reentrancy misses. Run after implementation |

---

## What NOT to Use

| Avoid | Why | Use Instead |
|-------|-----|-------------|
| OpenZeppelin `StorageSlot` | Operates on whole slot pointers — cannot express sub-slot packing of two uint128 values | Raw shift/mask as shown above |
| Solady `LibPack` / `PackedUserOperation` | Adds a new git dependency for functionality that two lines of inline arithmetic replace; increases audit surface | Inline `uint256(x) << 128 \| uint256(y)` |
| Second parallel mapping for double-buffer | Requires a new storage slot, doubles slot alignment risk in delegatecall modules | Bit-23 key encoding in existing `uint24` mapping key |
| `assembly` for packing | No gas advantage over optimizer-handled Solidity with `via_ir`; opaque to auditors | Solidity shift/cast with `unchecked` |
| Additional `bool` flags beyond the 3 specified | Slot 1 has 11 bytes remaining but each new flag adds delegatecall alignment surface | Use the minimum: `ticketWriteSlot`, `ticketsFullyProcessed`, `prizePoolFrozen` |

---

## Alternatives Considered

| Recommended | Alternative | When to Use Alternative |
|-------------|-------------|-------------------------|
| Bit-23 key encoding | Second `mapping(uint24 => address[])` for write slot | Only if level space > 2^23 — not possible in this game's lifetime |
| uint128 packed in uint256 | Two separate `uint128` storage vars in same slot | Acceptable if the two values are never mutated together; here they always are, so packing wins |
| `ticketWriteSlot` as `uint8` | `bool writeSlotIsOne` | uint8 enables XOR toggle idiom; bool would require conditional branch for swap |
| Load-once locals pattern | Inline `_getPrizePools()` / `_setPrizePools()` at each use site | For single-mutation functions, inline is fine; for multi-mutation functions (consolidatePrizePools, payDailyJackpot) load-once is strictly required |

---

## Version Compatibility

| Package | Compatible With | Notes |
|---------|-----------------|-------|
| Solidity 0.8.34 | forge 1.5.1 | Foundry auto-downloads the exact compiler version specified in `foundry.toml`; system solc (0.8.26) is not used |
| OpenZeppelin 5.4.0 | Solidity 0.8.34 | OZ 5.x requires 0.8.20+; compatible. No new OZ usage needed for this milestone |
| forge-std (submodule) | forge 1.5.1 | Already pinned; no update needed |

---

## Storage Layout Verification Commands

After implementing the storage changes, run these to confirm correctness:

```bash
# Verify Slot 1 packing (should show ticketWriteSlot at byte 18, etc.)
forge inspect contracts/storage/DegenerusGameStorage.sol:DegenerusGameStorage storage --root /path/to/project

# Verify no slot collisions between main contract and modules (must match exactly)
forge inspect contracts/DegenerusGame.sol:DegenerusGame storage-layout
forge inspect contracts/modules/DegenerusGameJackpotModule.sol:DegenerusGameJackpotModule storage-layout

# Gas snapshot baseline (run before implementation, compare after)
forge snapshot --match-test "testPurchase|testAdvance" --root /path/to/project
```

---

## Sources

- `/home/zak/Dev/PurgeGame/degenerus-audit/contracts/storage/DegenerusGameStorage.sol` — storage layout confirmed (Slot 1 padding, existing `uint24` mappings, `dailyTicketBudgetsPacked` precedent for packed slots) — HIGH confidence
- `/home/zak/Dev/PurgeGame/degenerus-audit/audit/PLAN-ALWAYS-OPEN-PURCHASES.md` — implementation plan, all code patterns — authoritative for this milestone
- `/home/zak/Dev/PurgeGame/degenerus-audit/foundry.toml` — `via_ir = true`, `optimizer_runs = 2`, `solc_version = "0.8.34"` — HIGH confidence
- `/home/zak/Dev/PurgeGame/degenerus-audit/node_modules/@openzeppelin/contracts/package.json` — OZ 5.4.0 confirmed — HIGH confidence
- Forge 1.5.1 build output — project compiles clean with 0.8.34, no errors — HIGH confidence

---
*Stack research for: double-buffered ticket queues, packed prize pool storage, prize pool freeze/unfreeze*
*Researched: 2026-03-11*
