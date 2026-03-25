# Unit 5: Mint + Purchase Flow -- Skeptic Review

**Agent:** Skeptic (Validator)
**Contracts:** DegenerusGameMintModule.sol (~1,167 lines), DegenerusGameMintStreakUtils.sol (62 lines)
**Date:** 2026-03-25

---

## Review Summary

| ID | Title | Mad Genius Verdict | Skeptic Verdict | Severity |
|----|-------|-------------------|-----------------|----------|
| F-01 | purchaseLevel cache vs recordMintData | INVESTIGATE | DOWNGRADE TO INFO | INFO |
| F-02 | claimableWinnings double-read | INVESTIGATE | FALSE POSITIVE | N/A |
| F-03 | Century bonus division safety | INVESTIGATE | DOWNGRADE TO INFO | INFO |
| F-04 | Ticket level routing stranding risk | INVESTIGATE | FALSE POSITIVE | N/A |
| F-05 | Write budget griefing via zero-owed entries | INVESTIGATE | DOWNGRADE TO INFO | INFO |
| F-06 | LCG trait prediction | INVESTIGATE | FALSE POSITIVE | N/A |

**Result:** 0 CONFIRMED vulnerabilities. 3 DOWNGRADE TO INFO. 3 FALSE POSITIVE.

---

## Finding Reviews

### F-01: purchaseLevel cache vs recordMintData

**Mad Genius Verdict:** INVESTIGATE (INFO)
**Skeptic Verdict:** DOWNGRADE TO INFO

**Analysis:** I independently verified the self-call chain. At `_purchaseFor` line 636, `purchaseLevel = level + 1` is cached. The self-call at `_callTicketPurchase` line 918 calls `IDegenerusGame(address(this)).recordMint{value}()` which delegates to `recordMintData`. I read `recordMintData` lines 175-284: it writes ONLY to `mintPacked_[player]` (lines 217, 237, 281). It does NOT write `level`, `price`, or any other Game FSM variable. The `level` variable is only written in `DegenerusGameAdvanceModule` during phase transitions. The cache is safe.

The Mad Genius correctly identified this as safe but flagged it as INVESTIGATE. I agree the implicit assumption that `level` does not change mid-transaction is worth documenting. The non-reentrancy guarantee from Game's routing ensures this.

**Disposition:** Informational note. No action needed.

---

### F-02: claimableWinnings double-read

**Mad Genius Verdict:** INVESTIGATE (INFO)
**Skeptic Verdict:** FALSE POSITIVE

**Analysis:** I verified lines 650 and 669 in `_purchaseFor`. Line 650 reads `claimableWinnings[buyer]` into `initialClaimable`. Line 669 reads it again as `uint256 claimable = claimableWinnings[buyer]` for the shortfall calculation. Between these two reads (lines 650-669), the code performs only:
- Line 652-661: local arithmetic on `remainingEth` and `lootboxFreshEth`
- Line 664: `payKind` check
- Line 665-667: local arithmetic on `lootboxFreshEth` and `shortfall`

No external calls, no storage writes, no function calls of any kind between the two reads. The value cannot change between reads. This is not even theoretically interesting.

**Reason for dismissal:** No state change possible between the two reads (lines 650-669 contain only local variable assignments and a revert check). The two reads will return identical values by EVM semantics.

---

### F-03: Century bonus division safety

**Mad Genius Verdict:** INVESTIGATE (INFO)
**Skeptic Verdict:** DOWNGRADE TO INFO

**Analysis:** I verified line 888: `uint256 maxBonus = (20 ether) / (priceWei >> 2)`. The concern is `priceWei >> 2 == 0` causing a division-by-zero revert.

The `priceWei` local is set from `price` at line 856. The storage variable `price` is initialized at `0.01 ether` (GameStorage line 312) and only updated during level transitions by the price curve logic. The minimum price is `0.01 ether` (level 0). At `priceWei = 0.01 ether = 10^16 wei`, `priceWei >> 2 = 2.5 * 10^15`. Division is safe.

Furthermore, the century bonus only activates when `targetLevel % 100 == 0` (line 880). The first century level is 100, by which point price has grown significantly above 0.01 ETH. The theoretical minimum price producing `priceWei >> 2 == 0` would require `priceWei < 4 wei`, which is economically impossible (would mean a ticket costs less than 1 wei).

Additionally, `costWei = (priceWei * quantity) / (4 * TICKET_SCALE)` at line 857, and `costWei == 0` reverts at line 858. For `costWei > 0`, we need `priceWei * quantity > 0`, so `priceWei > 0`. And `costWei >= TICKET_MIN_BUYIN_WEI = 0.0025 ether` at line 859 further guarantees non-trivial price.

**Disposition:** Informational note. Division by zero is impossible given economic constraints.

---

### F-04: Ticket level routing stranding risk

**Mad Genius Verdict:** INVESTIGATE (INFO)
**Skeptic Verdict:** FALSE POSITIVE

**Analysis:** The Mad Genius flagged that when `jackpotPhaseFlag == true && rngLockedFlag == false`, tickets route to `level` (current level). The concern is whether these tickets could be stranded.

I traced the ticket processing flow in `DegenerusGameAdvanceModule`. During jackpot phase, `advanceGame` calls `_runProcessTicketBatch(level)` which delegates to `processFutureTicketBatch(level)`. This drains the READ queue for the current level. Tickets purchased during jackpot phase for `level` go into the WRITE queue. At phase transition (`_endPhase`), `_swapTicketSlot` is called, swapping write and read queues. The next level's processing then drains the (now-read) queue containing tickets from the previous level.

The "last jackpot day fix" at lines 845-851 specifically handles the edge case where tickets purchased during the final jackpot day should route to `level + 1` (because the current level is about to transition). This fix checks if `cnt + step >= JACKPOT_LEVEL_CAP` and redirects accordingly.

**Reason for dismissal:** Tickets routed to `level` during jackpot phase are in the WRITE queue and get swapped to the READ queue at phase transition. They are processed during the next level's ticket drain. No stranding possible. The last-jackpot-day fix at lines 845-851 additionally prevents edge-case stranding.

---

### F-05: Write budget griefing via zero-owed entries

**Mad Genius Verdict:** INVESTIGATE (INFO)
**Skeptic Verdict:** DOWNGRADE TO INFO

**Analysis:** I verified the griefing economics. To create a zero-owed queue entry, an attacker must call `_queueTicketsScaled` with a quantity that rounds to 0 whole tickets and has a remainder that eventually rolls to 0. But `_queueTicketsScaled` at line 561 has `if (quantityScaled == 0) return` -- you cannot queue zero tickets. Any non-zero `quantityScaled` produces either `whole > 0` or `frac > 0`, meaning `owed > 0` or `rem > 0` in the packed value.

A zero-owed entry can only arise AFTER processing when the remainder roll loses (probability `(100 - rem) / 100`). The attacker cannot control whether the roll succeeds (VRF-dependent). They can create entries with small remainders (buying fractional tickets), but each still requires a purchase transaction with `costWei >= 0.0025 ETH` and gas costs.

The worst case: 357 budget units per batch call (cold storage), processing 357 zero entries per `advanceGame` call. With hundreds of zero entries, processing takes multiple `advanceGame` calls (each costs ~200K gas to the caller). The attacker's cost (hundreds of 0.0025 ETH purchases + gas) far exceeds the griefing impact (slightly delaying ticket processing).

**Disposition:** Informational note. Economically unviable griefing vector.

---

### F-06: LCG trait prediction

**Mad Genius Verdict:** INVESTIGATE (INFO)
**Skeptic Verdict:** FALSE POSITIVE

**Analysis:** The Mad Genius noted that an observer knowing `rngWordCurrent` can predict trait assignments. This is correct and by-design.

Trait generation is intentionally deterministic given the VRF word. The VRF word (`rngWordCurrent`) is unknown at the time tickets are purchased (committed via VRF request). By the time the VRF word is revealed and traits are generated in `processFutureTicketBatch`, the purchase commitment is already locked. An observer can predict traits after VRF fulfillment, but this is harmless -- traits are non-transferable burn tickets used for jackpot eligibility, not tradeable assets.

**Reason for dismissal:** Deterministic trait generation from VRF is the intended design. The VRF word is unknown at commitment time. Post-reveal prediction is harmless.

---

## Independent Verification of Critical Areas

### 1. _raritySymbolBatch Assembly Verification

I independently traced the Yul assembly at lines 502-536:

**Storage slot for `traitBurnTicket[lvl]`:**
```
levelSlot = keccak256(uint256(lvl) || traitBurnTicket.slot)
```
Solidity layout for `mapping(uint24 => T)`: data at `keccak256(abi.encode(key, slot))`. The code `mstore(0x00, lvl)` zero-pads `lvl` to 32 bytes, `mstore(0x20, traitBurnTicket.slot)` places the slot number, and `keccak256(0x00, 0x40)` hashes the concatenation. **CORRECT.**

**Fixed array element:** `elem = levelSlot + traitId`. For a fixed-size array `address[256]` of dynamic arrays, element `i` has its length at `base + i`. **CORRECT.**

**Dynamic array data start:** `data = keccak256(elem)`. Standard Solidity: dynamic array data begins at `keccak256(length_slot)`. **CORRECT.**

**Write position:** `dst = data + len`, writing `occurrences` entries. Then `sstore(elem, len + occurrences)` updates length. Length is updated BEFORE data writes (line 518 before line 524), but this is safe because EVM reverts roll back all state changes atomically. **CORRECT.**

**Skeptic independent verdict: CORRECT** -- Assembly matches Solidity storage layout. No out-of-bounds or overwrite risk.

### 2. Self-Call Re-Entry (recordMint)

I independently verified the self-call at line 918. `recordMint` in DegenerusGame:
1. Validates payment
2. Deducts from `claimableWinnings[payer]` and `claimablePool` (for Claimable/Combined)
3. Adds to `currentPrizePool` and `prizePoolsPacked`
4. Delegatecalls `recordMintData` (writes `mintPacked_[payer]`)

Post-return, `_callTicketPurchase` uses only:
- `value`, `payKind`, `costWei`, `freshEth`, `freshBurnie` -- all locals/parameters, not storage reads
- `priceWei` -- cached from `price`, not written by `recordMint`
- `adjustedQty32` -- computed before the self-call

No stale-cache issues. **Skeptic independent verdict: SAFE.**

### 3. Ticket Level Routing (lines 842-851)

I independently verified by tracing the AdvanceModule's ticket processing flow:
- Purchase phase: `targetLevel = level + 1` (write queue)
- Jackpot phase normal: `targetLevel = level` (write queue for current level)
- Last jackpot day: `targetLevel = level + 1` (redirect to next level)
- Phase transition: `_swapTicketSlot` swaps write/read

All queue entries are eventually drained by `processFutureTicketBatch` for the appropriate level. **Skeptic independent verdict: SAFE.**

### 4. claimableWinnings Deduction (lines 669-677)

I verified:
- `claimable <= shortfall` reverts (line 671) -- prevents underflow and preserves 1-wei sentinel
- `claimableWinnings[buyer] = claimable - shortfall` (line 673) -- exact deduction
- `claimablePool -= shortfall` (line 675) -- paired deduction

The 1-wei sentinel is preserved because `claimable <= shortfall` reverts. If `claimable = 1` (sentinel) and `shortfall >= 1`, it reverts. The player cannot spend their sentinel wei. **CORRECT.**

---

## Independent Checklist Verification (VAL-04)

I independently read both contracts and verified:
- **DegenerusGameMintModule.sol:** All 16 functions (5 external + 7 private + 4 view/pure) are on the checklist. No state-changing function was omitted.
- **DegenerusGameMintStreakUtils.sol:** Both functions (_recordMintStreakForLevel, _mintStreakEffective) are on the checklist.
- **Inherited helpers from GameStorage:** _queueTicketsScaled, _awardEarlybirdDgnrs, _currentMintDay, _setMintDay, _simulatedDayIndex, _tqReadKey, _tqFarFutureKey, _tqWriteKey, _isDistressMode, _getPrizePools, _setPrizePools, _getPendingPools, _setPendingPools, _getNextPrizePool, _lootboxTierToBps are all utility functions. The ones that perform state changes within MintModule's call trees (_queueTicketsScaled, _awardEarlybirdDgnrs) are documented as C10 and C11.

**Verdict:** Complete. No state-changing function omitted from the checklist.
