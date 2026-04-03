# Pitfalls Research

**Domain:** Storage repacking, module elimination, and uint downsizing in a delegatecall-module Solidity architecture
**Researched:** 2026-04-02
**Confidence:** HIGH (domain-specific, derived from architecture analysis of actual codebase)

## Critical Pitfalls

### Pitfall 1: Slot Shift Cascade — Moving Variables Between EVM Slots

**What goes wrong:**
Moving `ticketsFullyProcessed` and `gameOverPossible` from slot 1 into slot 0 (which has 2 bytes free) changes the byte offset of every variable that followed them in slot 1. Downsizing `currentPrizePool` from uint256 (slot 2) to uint128 and packing it into slot 1 eliminates old slot 2 entirely, shifting every subsequent slot number down by one. Every `uint256` variable after `currentPrizePool` (prizePoolsPacked, rngWordCurrent, vrfRequestId, totalFlipReversals, dailyTicketBudgetsPacked, etc.) now occupies slot N-1 instead of slot N. Every mapping root shifts too, changing the keccak256(key . slot) derivation for all mapping entries. On a fresh deploy this is fine because there is no existing state, but the mechanical risk is forgetting to recompile all contracts against the new layout.

**Why it happens:**
Developers think "I only moved two bools" but forget the EVM assigns slots sequentially. Removing a full-width variable from the middle shifts everything below it.

**How to avoid:**
1. Before touching storage, run `forge inspect DegenerusGameStorage storageLayout` and capture the full slot map as the "before" baseline.
2. After repacking, run it again and produce a "before vs after" diff.
3. Verify every slot that shifted. ALL modules (AdvanceModule, JackpotModule, MintModule, EndgameModule, GameOverModule, WhaleModule, DecimatorModule, LootboxModule, PayoutUtils) inherit DegenerusGameStorage. A single mismatch = silent storage corruption at runtime.
4. Since this is a fresh deploy (no proxy, no upgrade), slot shifts are safe as long as ALL contracts compile against the same new layout. The risk is forgetting to recompile a module or leaving stale assembly that hardcodes slot numbers.

**Warning signs:**
- Any assembly block referencing `.slot` or hardcoded slot numbers
- Any `forge inspect` diff showing a variable at a different slot than expected
- Tests passing individually but failing in integration (module reads wrong slot)

**Phase to address:**
Storage repack phase (first phase). Must be done atomically with full slot audit before any other changes.

---

### Pitfall 2: Assembly Slot Hardcoding Survives Repack

**What goes wrong:**
The codebase uses inline assembly in several places (e.g., `_revertDelegate`, ticket queue helpers, potential slot 0 packed reads). If any assembly block references a storage slot by number rather than by `.slot` syntax, it will silently read/write the wrong variable after repacking. Solidity's type system cannot catch assembly-level slot references.

**Why it happens:**
Assembly blocks are invisible to the compiler's storage layout system. A hardcoded `sload(2)` that used to read `currentPrizePool` will read `prizePoolsPacked` after the repack. The compiler emits no warning.

**How to avoid:**
1. Grep the entire codebase for `sload(`, `sstore(`, and `.slot` in assembly blocks.
2. For each hit, verify the referenced slot against the new layout.
3. Replace any hardcoded numeric slots with `variableName.slot` where possible.
4. If byte offsets within slot 0 change (they will, since two bools are being added at the end), every assembly read/write of slot 0 must be updated to reflect the new positions.

**Warning signs:**
- `grep -rn 'sload\|sstore\|\.slot' contracts/` returning hits in storage or module files
- Tests passing for some functions but not others after repack

**Phase to address:**
Storage repack phase. Must be audited as part of the slot diff.

---

### Pitfall 3: Delegatecall Module Reads Stale Layout After Repack

**What goes wrong:**
All 8+ modules inherit `DegenerusGameStorage` and are deployed as separate contracts. When DegenerusGame does `module.delegatecall(...)`, the module's compiled bytecode contains hardcoded slot offsets baked in at compile time. If a module is compiled against the OLD storage layout while DegenerusGame uses the NEW layout, the delegatecall executes with wrong slot offsets. This corrupts storage silently — there is no runtime check that layouts match.

**Why it happens:**
In this architecture, `DegenerusGameStorage` is the single source of truth for all slot assignments. The safety guarantee only holds if ALL contracts are compiled together from the same source. The pitfall is incremental compilation or stale build artifacts.

**How to avoid:**
1. After modifying `DegenerusGameStorage.sol`, do a full `forge clean && forge build` to ensure every contract recompiles.
2. Run `forge inspect <Contract> storageLayout` for EVERY contract that inherits DegenerusGameStorage and diff them against each other. They must be byte-for-byte identical in their storage layout output.
3. Deploy all contracts together in the deterministic CREATE nonce sequence. No partial deploys.

**Warning signs:**
- `forge inspect` showing different slot assignments between DegenerusGame and any module
- Stale build artifacts in `out/` directory
- Module tests passing in isolation but failing in integration

**Phase to address:**
Storage repack phase (verification step). Also: delta audit phase must re-verify all layouts via `forge inspect`.

---

### Pitfall 4: uint256 to uint128 Downsize — Intermediate Arithmetic Overflow

**What goes wrong:**
`currentPrizePool` is being downsized from `uint256` to `uint128`. A uint128 maxes at ~3.4 * 10^38 wei (~3.4 * 10^20 ETH) — far exceeding total ETH supply. So value overflow is not a realistic concern. The real dangers are:

1. **Intermediate arithmetic overflow:** Expressions like `(currentPrizePool * percentage) / 100` where `currentPrizePool` is first multiplied. If the multiplication happens in uint128 context (variable is typed uint128 and multiplied before widening), Solidity 0.8.34 will revert on overflow. This is a liveness/DoS issue, not a funds-at-risk issue. But even a temporary DoS on `advanceGame` is critical.

2. **Type mismatch with callers:** Many callers currently receive `currentPrizePool` as `uint256`. If the internal variable becomes uint128 but callers pass it to functions expecting uint256, implicit widening handles this. But if callers then pass the widened value to functions that narrow it back and multiply in uint128 context, overflow can occur.

3. **Packing into slot 1:** If `currentPrizePool` becomes uint128 packed into slot 1 alongside existing fields, all access must go through proper getter/setter helpers. Direct reads of the raw slot return garbage.

**Why it happens:**
Developers verify the value range fits in uint128 (correct) but miss that intermediate arithmetic may not, or that callers assume uint256 return types.

**How to avoid:**
1. Search every callsite of `currentPrizePool` for multiplication expressions. Verify the multiply happens in uint256 context (cast BEFORE multiply, not after).
2. Create `_getCurrentPrizePool()` / `_setCurrentPrizePool()` helper functions matching the existing `_getFuturePrizePool` pattern that handle packing/unpacking and return uint256.
3. Never allow direct reads of the packed slot — all access through helpers.
4. The external view `currentPrizePoolView()` must continue returning `uint256` for ABI compatibility.

**Warning signs:**
- Any direct reference to `currentPrizePool` without going through a helper after it becomes packed
- Solidity compiler warnings about implicit narrowing conversions
- Multiplication of uint128 values before casting to uint256

**Phase to address:**
Storage repack phase. The helper pattern is well-established (prizePoolsPacked uses it). Follow the exact same pattern.

---

### Pitfall 5: EndgameModule Elimination — Missing Callsite Rewiring

**What goes wrong:**
EndgameModule has 3 external entry points called via delegatecall:
- `runRewardJackpots(uint24, uint256)` — called from AdvanceModule._runRewardJackpots
- `rewardTopAffiliate(uint24)` — called from AdvanceModule._rewardTopAffiliate
- `claimWhalePass(address)` — called from DegenerusGame (line ~1643)

Plus private functions (`_addClaimableEth`, `_runBafJackpot`, `_awardJackpotTickets`, `_jackpotTicketRoll`) that must move to whichever module absorbs the external functions.

If ANY callsite is missed, the delegatecall will target a non-existent or wrong contract address. Since `ContractAddresses.GAME_ENDGAME_MODULE` is a compile-time constant, removing the module means either:
- (a) Removing the constant entirely and updating all callsites — forces compile errors at every missed reference, or
- (b) Redirecting the constant to the absorbing module's address — silent, error-prone.

Option (a) is the only safe approach.

**Why it happens:**
The 3 external callsites are easy to find. The hidden danger is the `IDegenerusGameEndgameModule` interface references scattered across files, and the `IDegenerusGame(address(this)).runDecimatorJackpot(...)` self-call pattern inside EndgameModule's `runRewardJackpots`. When code moves to a new module, this self-call must still resolve correctly.

**How to avoid:**
1. Delete `GAME_ENDGAME_MODULE` from ContractAddresses.sol (user's responsibility per project memory).
2. Delete `IDegenerusGameEndgameModule` interface. This produces compile errors at every import and selector reference.
3. Fix each compile error by rewiring to the absorbing module.
4. After fixing all errors, grep for string "Endgame" and "ENDGAME" across the entire codebase to catch comments and documentation references.
5. Verify `IDegenerusGame(address(this)).runDecimatorJackpot(...)` still resolves correctly in the new location (it should — it calls through Game's external interface, not the Endgame module's).

**Warning signs:**
- Any remaining reference to `GAME_ENDGAME_MODULE` or `IDegenerusGameEndgameModule` after cleanup
- `forge build` succeeding with fewer errors than expected (missed a file)
- Deploy script still referencing EndgameModule

**Phase to address:**
Module elimination phase. Compile-error-driven approach ensures completeness.

---

### Pitfall 6: rebuyDelta Reconciliation Pattern Must Survive the Move

**What goes wrong:**
`runRewardJackpots` contains a critical cache-overwrite reconciliation pattern (the `rebuyDelta` logic at lines 246-259 of EndgameModule). This was the v4.4 fix for the BAF cache-overwrite bug where auto-rebuy contributions written directly to `futurePrizePool` storage during nested calls were silently clobbered by the cached `futurePoolLocal` write-back. During the move to a new module, this pattern must be preserved exactly. If the `baseFuturePool` snapshot or the `rebuyDelta` calculation is accidentally altered, auto-rebuy contributions will be silently lost — the exact bug v4.4 fixed.

**Why it happens:**
The reconciliation logic is subtle and non-obvious. A developer moving the function might "clean up" the code and accidentally remove or reorder the snapshot/reconciliation steps.

**How to avoid:**
1. Move `runRewardJackpots` as a verbatim copy. Do not refactor during the move.
2. After the move, run the existing `BafRebuyReconciliation.t.sol` Foundry test.
3. The delta audit phase must specifically re-verify this pattern.

**Warning signs:**
- Any diff in `runRewardJackpots` beyond module-name and import changes
- `BafRebuyReconciliation.t.sol` test failure
- Missing `baseFuturePool` snapshot variable

**Phase to address:**
Module elimination phase. Copy verbatim, verify with existing test, then delta audit confirms.

---

### Pitfall 7: Slot 0 Byte Budget Overflow

**What goes wrong:**
Slot 0 currently uses 30 bytes (2 bytes padding). The plan moves `ticketsFullyProcessed` (bool, 1 byte) and `gameOverPossible` (bool, 1 byte) from slot 1 into slot 0. That fills slot 0 to exactly 32 bytes — zero padding remaining. If the byte accounting is wrong by even 1 byte, the last variable silently spills into slot 1, corrupting whatever is packed there. The Solidity compiler does NOT warn about this — it silently starts a new slot.

**Why it happens:**
Manual byte counting across 13+ variables in a single slot is error-prone. The slot 0 header comment says "30 bytes used (2 bytes padding)" but comments can be stale. Only the compiler output is authoritative.

**How to avoid:**
1. After adding the two bools to slot 0, run `forge inspect DegenerusGameStorage storageLayout` and verify slot 0 contains exactly 32 bytes and the variable immediately after starts at slot 1.
2. Update the slot 0 header comment to reflect 32 bytes used, 0 padding.
3. If any future feature needs another flag in slot 0, it will not fit. Accept this constraint — document it.

**Warning signs:**
- `forge inspect` showing a variable at an unexpected slot
- Slot 0 comment still saying "2 bytes padding" after the change
- A "slot 1" variable appearing at slot 0 in `forge inspect` output

**Phase to address:**
Storage repack phase. `forge inspect` is the only authoritative check.

---

### Pitfall 8: Slot 1 New Layout — currentPrizePool Packing Errors

**What goes wrong:**
After moving `ticketsFullyProcessed` and `gameOverPossible` out of slot 1 and downsizing `currentPrizePool` from uint256 to uint128, the new slot 1 would contain: `purchaseStartDay` (uint48, 6 bytes), `ticketWriteSlot` (uint8, 1 byte), `prizePoolFrozen` (bool, 1 byte), and `currentPrizePool` (uint128, 16 bytes) = 24 bytes total, 8 bytes padding. This fits.

The danger: if getter/setter helpers for slot 1's packed fields use incorrect bit shifts or masks, reads/writes corrupt adjacent fields. The existing `prizePoolsPacked` pattern (symmetric 128/128 split) is clean, but a slot with 48+8+8+128 bits is asymmetric and requires more careful arithmetic if accessed via assembly.

**Why it happens:**
Solidity handles the packing automatically for declared storage variables. The pitfall only materializes if someone writes assembly optimization for slot 1 access or if the variable ordering within the slot is wrong (e.g., putting uint128 before the smaller types, which changes the packing).

**How to avoid:**
1. Let Solidity handle the packing — declare variables in the correct order and let the compiler assign offsets.
2. Do NOT use manual assembly for slot 1 access.
3. If helpers are needed (like `_getCurrentPrizePool()`), have them read/write the Solidity variable directly, not via assembly slot manipulation.
4. Verify with `forge inspect` that the packing matches design intent.

**Warning signs:**
- Assembly blocks reading slot 1 with hardcoded masks/shifts
- Helper functions using `sload`/`sstore` instead of Solidity variable access
- `currentPrizePool` getter returning wrong values in tests

**Phase to address:**
Storage repack phase. Prefer Solidity-managed packing over assembly in all cases.

---

### Pitfall 9: Event Signature Continuity After Module Move

**What goes wrong:**
EndgameModule emits 4 events: `AutoRebuyExecuted`, `RewardJackpotsSettled`, `AffiliateDgnrsReward`, `WhalePassClaimed`. When these functions move to a different module, the events will still be emitted from DegenerusGame's address (via delegatecall) with the same signatures, so indexers are unaffected. However, if events are accidentally duplicated (defined in both old and new module files) or if parameter types change during the move, the ABI changes and indexers break.

**Why it happens:**
Copy-paste of event definitions during consolidation. If the event is defined in the module file AND in an interface, there are two sources of truth that can diverge.

**How to avoid:**
1. Events should be defined in ONE place — either the interface or the storage contract, not both.
2. After the move, verify event signatures match by comparing ABI output before and after.
3. Run the full test suite and verify `expectEmit` assertions still pass.

**Warning signs:**
- Duplicate event definitions in multiple files
- ABI diff showing changed event signatures
- Hardhat/Foundry tests with `expectEmit` failing

**Phase to address:**
Module elimination phase. Mechanical — verify ABI output matches before/after.

---

### Pitfall 10: Deploy Order and ContractAddresses Desync

**What goes wrong:**
The 23-contract deploy uses CREATE nonce prediction (`ContractAddresses` bakes addresses at compile time). Eliminating EndgameModule means one fewer contract in the deploy sequence. If the deploy order changes without updating `ContractAddresses.sol` nonce predictions, every contract deployed after the removed one gets the wrong address. The entire protocol becomes non-functional.

**Why it happens:**
`ContractAddresses` uses deterministic CREATE addresses based on deployer nonce. Remove one contract from the sequence = every subsequent nonce shifts by -1.

**How to avoid:**
1. User manages `ContractAddresses.sol` (per project memory: NEVER checkout/restore/modify ContractAddresses.sol).
2. Document exactly which contract is removed and where it sat in the deploy order.
3. The deploy script must be updated to skip the removed contract.
4. All nonce predictions after the removed contract must be recalculated by the user.

**Warning signs:**
- `ContractAddresses` still containing `GAME_ENDGAME_MODULE` after elimination
- Deploy script still deploying EndgameModule
- Integration tests failing with "call to non-contract address"

**Phase to address:**
Final verification phase. User handles ContractAddresses; code changes must document the deploy order impact.

## Technical Debt Patterns

| Shortcut | Immediate Benefit | Long-term Cost | When Acceptable |
|----------|-------------------|----------------|-----------------|
| Copy-paste EndgameModule functions without cleanup | Fast, safe move | Dead imports, stale comments, duplicate event defs | During the move phase only — cleanup MUST follow in same phase |
| Skip delta audit after repack | Saves 1 phase | Silent storage corruption undetected until production | Never |
| Hardcode new slot numbers in assembly | Faster than refactoring assembly | Next repack breaks it again | Never — use `.slot` syntax |
| Leave `GAME_ENDGAME_MODULE` pointing to absorbing module | Zero callsite changes needed | Confusing indirection, stale naming, misleading audit trail | Never — delete and rewire |

## Integration Gotchas

| Integration | Common Mistake | Correct Approach |
|-------------|----------------|------------------|
| AdvanceModule calling reward jackpots | Changing delegatecall target but not the selector | Delete old interface, add new selector from absorbing module's interface |
| DegenerusGame calling claimWhalePass | Leaving call pointing at GAME_ENDGAME_MODULE constant | Rewire to new module constant; delete old constant |
| Test suite (BafRebuyReconciliation.t.sol) | Not updating deploy helper to exclude EndgameModule | Deploy helper must match new 22-contract sequence |
| GameOverModule accessing currentPrizePool | Assuming uint256 storage type when it is now uint128 | Access via helper that returns uint256 (implicit widening) |
| External view (currentPrizePoolView) | Returning uint128, breaking ABI | Keep return type as uint256; Solidity implicit widening handles it |
| JackpotModule `currentPrizePool -= paidDailyEth` | Direct access of packed variable bypasses packing logic | Must go through `_setCurrentPrizePool` helper (or rely on Solidity auto-packing if directly named) |

## Performance Traps

| Trap | Symptoms | Prevention | When It Breaks |
|------|----------|------------|----------------|
| Extra SLOAD from slot 1 packing | currentPrizePool reads now touch slot 1 (shared with other vars) instead of dedicated slot 2 | Solidity auto-caches slot reads within a function; cold SLOAD cost is the same | Not a real concern — may actually save gas if slot 1 is already loaded |
| Slot 0 at 32/32 bytes — no room for future additions | Next feature requiring a slot 0 bool forces another repack | Accept this constraint; future additions go to new slots or a new packed uint256 | When next feature flag is needed |

## Security Mistakes

| Mistake | Risk | Prevention |
|---------|------|------------|
| Not running `forge inspect` for ALL inheriting contracts after repack | Storage corruption undetected — modules read/write wrong slots | Delta audit phase MUST compare `forge inspect` output for all contracts |
| Moving `_addClaimableEth` without its rebuyDelta reconciliation context | Auto-rebuy ETH silently lost (v4.4 regression) | Move entire function cluster as a unit; run BafRebuyReconciliation test |
| Leaving stale slot header comments in DegenerusGameStorage.sol | C4A wardens flag as "incorrect documentation" (QA finding costs real money) | Update ALL slot header comments + architecture overview NatSpec |
| Direct `currentPrizePool` variable access after it becomes packed in slot 1 | Reads/writes corrupt adjacent `purchaseStartDay`, `ticketWriteSlot`, `prizePoolFrozen` fields | All access through getter/setter helpers (or Solidity named variable access which auto-handles packing) |

## "Looks Done But Isn't" Checklist

- [ ] **Storage repack:** `forge inspect` run for ALL contracts inheriting DegenerusGameStorage — not just the storage contract
- [ ] **Storage repack:** Before/after slot diff produced and reviewed
- [ ] **Storage repack:** Assembly grep (`sload`, `sstore`, `.slot`) — every hit verified against new layout
- [ ] **Module elimination:** `GAME_ENDGAME_MODULE` constant removed from ContractAddresses (user's responsibility)
- [ ] **Module elimination:** `IDegenerusGameEndgameModule` interface file deleted
- [ ] **Module elimination:** All 3 delegatecall callsites rewired (AdvanceModule x2, DegenerusGame x1)
- [ ] **Module elimination:** `DegenerusGameEndgameModule.sol` file deleted
- [ ] **Module elimination:** Deploy script updated to deploy 22 contracts instead of 23
- [ ] **Slot comments:** ALL slot header comments updated (slot 0 = 32 bytes, slot 1 = new layout, old slot 2 occupant gone)
- [ ] **Slot comments:** Architecture overview NatSpec at top of DegenerusGameStorage updated (module list, slot diagram)
- [ ] **uint128 downsize:** `currentPrizePoolView()` still returns uint256
- [ ] **uint128 downsize:** Every arithmetic expression involving currentPrizePool verified for intermediate overflow
- [ ] **rebuyDelta pattern:** BafRebuyReconciliation.t.sol passes after move
- [ ] **Event continuity:** ABI diff shows zero event signature changes
- [ ] **Test baseline:** Full Hardhat + Foundry suites pass with zero new failures
- [ ] **Grep sweep:** Zero references to "EndgameModule" or "ENDGAME_MODULE" remain in Solidity files
- [ ] **Self-call pattern:** `IDegenerusGame(address(this)).runDecimatorJackpot(...)` still resolves in new module

## Recovery Strategies

| Pitfall | Recovery Cost | Recovery Steps |
|---------|---------------|----------------|
| Slot shift cascade (missed variable) | MEDIUM | Re-run `forge inspect`, identify misaligned variable, fix layout, recompile all |
| Assembly hardcoded slot | HIGH | Grep all assembly, audit each slot reference, fix and re-test |
| Stale module compilation | LOW | `forge clean && forge build`, verify with `forge inspect` |
| currentPrizePool intermediate overflow | LOW | Cast to uint256 before multiply; or widen back if pattern is pervasive |
| Missing callsite rewiring | LOW | Delete constant/interface, fix each compile error |
| Deploy order desync | HIGH | Recalculate all nonce-predicted addresses; user redoes ContractAddresses |
| rebuyDelta pattern broken | HIGH | Revert function to verbatim copy from EndgameModule; run reconciliation test |
| Slot 0 byte overflow | LOW | `forge inspect` immediately reveals the spill; reorder variables |

## Pitfall-to-Phase Mapping

| Pitfall | Prevention Phase | Verification |
|---------|------------------|--------------|
| Slot shift cascade | Storage repack | `forge inspect` all contracts, before/after diff |
| Assembly slot hardcoding | Storage repack | Grep `sload\|sstore\|\.slot` in assembly blocks |
| Stale module layout | Storage repack | `forge clean && forge build`, cross-contract `forge inspect` |
| uint128 intermediate overflow | Storage repack | Review every `currentPrizePool` arithmetic expression |
| Missing callsite rewiring | Module elimination | Delete constant + interface, fix compile errors |
| Event signature changes | Module elimination | ABI diff before/after |
| rebuyDelta pattern broken | Module elimination | BafRebuyReconciliation.t.sol must pass |
| Slot 0 byte overflow | Storage repack | `forge inspect` slot 0 = exactly 32 bytes |
| Slot 1 packing errors | Storage repack | `forge inspect` slot 1 layout matches design |
| Deploy order desync | Final verification | User manages ContractAddresses; document impact |

## Sources

- Direct codebase analysis of `DegenerusGameStorage.sol` (slots 0-2 layout, 30 bytes slot 0, 9 bytes slot 1, uint256 slot 2)
- Direct codebase analysis of `DegenerusGameEndgameModule.sol` (3 external entry points, 4 events, rebuyDelta reconciliation pattern)
- Project memory: v4.4 BAF cache-overwrite bug fix establishing the rebuyDelta reconciliation pattern
- Project memory: ContractAddresses.sol is user-managed (NEVER modify)
- Project memory: all prior `forge inspect` verification passes across v7.0, v10.3, v15.0 milestones
- EVM storage layout specification: sequential slot assignment, left-to-right packing within slots
- Solidity 0.8.34 compiler behavior: automatic overflow checks in checked context, storage packing rules
- `forge inspect` as authoritative storage layout verification tool (used successfully in 3+ prior milestones)

---
*Pitfalls research for: v16.0 Module Consolidation & Storage Repack*
*Researched: 2026-04-02*
