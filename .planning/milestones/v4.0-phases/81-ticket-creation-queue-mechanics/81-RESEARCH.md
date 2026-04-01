# Phase 81: Ticket Creation & Queue Mechanics - Research

**Researched:** 2026-03-23
**Domain:** Solidity smart contract audit -- ticket creation entry points and double-buffer queuing system
**Confidence:** HIGH

## Summary

Phase 81 requires exhaustive tracing of every ticket creation entry point and the double-buffer queuing system in the Degenerus Protocol. This is a re-audit phase: all prior audit prose (v3.8, v3.9) is treated as unverified and every claim must be confirmed with file:line citations against actual Solidity, with discrepancies flagged.

The ticket queue system uses three key spaces: Slot 0 (raw level), Slot 1 (bit 23 set), and Far-Future (bit 22 set). The `ticketWriteSlot` variable toggles which of Slot 0/Slot 1 is the write buffer vs read buffer. Far-future tickets (targeting > level+6) go to the FF key space, independent of the double-buffer. All three queue helper functions (`_queueTickets`, `_queueTicketsScaled`, `_queueTicketRange`) plus wrapper `_queueLootboxTickets` have rngLockedFlag guards on FF writes with `phaseTransitionActive` exemption.

There are 6 distinct external entry points that create tickets, plus 4 internal paths from advanceGame/jackpot processing. A notable finding during research: the current `_awardFarFutureCoinJackpot` code (JM:2543) reads ONLY from `_tqFarFutureKey`, not from the combined pool (read buffer + FF key) documented in the v3.9 Phase 77 summary and RNG commitment window proof. Commit `2bf830a2` reverted the combined pool approach after Phase 77. This means the v3.9 commitment window proof at Section 2 (backward trace) contains stale claims about combined pool read behavior. Additionally, `sampleFarFutureTickets` (DG:2681) still uses `_tqWriteKey` -- a view function, so not a vulnerability, but a correctness issue that may return stale/wrong data.

**Primary recommendation:** Systematically enumerate every ticket creation entry point with file:line citations, document the three key spaces and double-buffer swap mechanics, verify rngLockedFlag/prizePoolFrozen behavior on each path, and flag discrepancies between current code and prior audit documentation.

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| TKT-01 | Every external function that queues tickets is identified with file:line, caller chain, and storage reads/writes | 6 external entry points + 4 internal paths identified from grep analysis; exact file:line locations mapped for all `_queueTickets`/`_queueTicketsScaled`/`_queueTicketRange` callers |
| TKT-02 | For each ticket creation path: what determines ticket count, target level, and queue key selection | Ticket count varies per path (fixed constants, price-derived, quantity-scaled); target level depends on current level + offsets per module; queue key is `_tqWriteKey` (near-future) or `_tqFarFutureKey` (far-future, targetLevel > level+6) |
| TKT-03 | Every ticket creation path's rngLockedFlag and prizePoolFrozen behavior is documented | rngLockedFlag guard in all three queue helpers (GS:545, GS:573, GS:622); prizePoolFrozen affects pool routing but not ticket creation directly; `purchaseDeityPass` has its own rngLockedFlag check (WM:475) |
| TKT-04 | All callers of _queueTickets, _queueTicketsScaled, _queueTicketRange, and direct ticketQueue pushes are enumerated | Complete caller enumeration from grep: 10+ distinct call sites across MintModule, WhaleModule, LootboxModule, DecimatorModule, EndgameModule, JackpotModule, AdvanceModule, and DegenerusGame constructor |
| TKT-05 | Double-buffer formulas (_tqReadKey, _tqWriteKey, _tqFarFutureKey) documented with ticketWriteSlot relationship | All three formulas traced at GS:686-700; three disjoint key spaces [0x000000-0x3FFFFF], [0x400000-0x7FFFFF], [0x800000-0xBFFFFF] confirmed; ticketWriteSlot is XOR-toggled (GS:712) |
| TKT-06 | _swapAndFreeze / _swapTicketSlot trigger conditions and complete code path list documented | _swapTicketSlot at GS:709-714 called by _swapAndFreeze (GS:719-725) and directly by AdvanceModule:720; _swapAndFreeze called at AM:233 on daily RNG request; freeze zeros pending accumulators unless already frozen |
| DSC-01 | Every discrepancy between prior audit prose and actual code flagged with [DISCREPANCY] tag | Key discrepancy already identified: v3.9 RNG commitment window proof (Section 2) describes combined pool read in _awardFarFutureCoinJackpot, but current code reads FF key only (reverted in 2bf830a2); sampleFarFutureTickets still uses _tqWriteKey |
| DSC-02 | Every new issue not in prior audits flagged with [NEW FINDING] tag | sampleFarFutureTickets using _tqWriteKey (DG:2681) is a view function correctness issue not flagged in prior audits |
</phase_requirements>

## Architecture Patterns

### Contract Architecture (Delegatecall)

DegenerusGame is the main contract holding all state. Modules execute via delegatecall, sharing the storage layout defined in `DegenerusGameStorage.sol`. Key modules for ticket creation:

| Module | File | Ticket Functions |
|--------|------|-----------------|
| MintModule | `contracts/modules/DegenerusGameMintModule.sol` (1183 lines) | `purchase`, `purchaseCoin`, `purchaseBurnieLootbox` via `_queueTicketsScaled` |
| WhaleModule | `contracts/modules/DegenerusGameWhaleModule.sol` (822 lines) | `purchaseWhaleBundle`, `purchaseLazyPass`, `purchaseDeityPass` via `_queueTickets` |
| LootboxModule | `contracts/modules/DegenerusGameLootboxModule.sol` (1864 lines) | `openLootBox`, `openBurnieLootBox` via `_queueTicketsScaled`, `_activateWhalePass` via `_queueTickets` |
| DecimatorModule | `contracts/modules/DegenerusGameDecimatorModule.sol` (930 lines) | `claimDecimatorJackpot` auto-rebuy via `_queueTickets` |
| EndgameModule | `contracts/modules/DegenerusGameEndgameModule.sol` (555 lines) | `claimWhalePass` via `_queueTicketRange` and auto-rebuy via `_queueTickets` |
| JackpotModule | `contracts/modules/DegenerusGameJackpotModule.sol` (2794 lines) | Daily jackpot ticket distribution via `_distributeTicketJackpot` -> `_queueTickets`; auto-rebuy via `_processAutoRebuy` -> `_queueTickets`; earlybird lootbox jackpot via `_queueTickets` |
| AdvanceModule | `contracts/modules/DegenerusGameAdvanceModule.sol` (1558 lines) | `_processPhaseTransition` -> `_queueTickets` (vault perpetual tickets) |
| DegenerusGame | `contracts/DegenerusGame.sol` (2848 lines) | Constructor pre-queues vault tickets for levels 1-100 |

### Three Key Spaces

```
TICKET_SLOT_BIT        = 1 << 23  (0x800000)  -- GS:154
TICKET_FAR_FUTURE_BIT  = 1 << 22  (0x400000)  -- GS:162

Key Space 0 (Slot 0): lvl & 0x3FFFFF              -- levels 0x000000 to 0x3FFFFF
Key Space 1 (FF):     lvl | TICKET_FAR_FUTURE_BIT  -- levels 0x400000 to 0x7FFFFF
Key Space 2 (Slot 1): lvl | TICKET_SLOT_BIT        -- levels 0x800000 to 0xBFFFFF

Disjoint for all lvl < 2^22 = 4,194,303
```

### Double-Buffer Key Encoding (GS:686-700)

```solidity
// Write key: where new tickets go
function _tqWriteKey(uint24 lvl) internal view returns (uint24) {
    return ticketWriteSlot != 0 ? lvl | TICKET_SLOT_BIT : lvl;
}
// ticketWriteSlot=0: write to Slot 0, read from Slot 1
// ticketWriteSlot=1: write to Slot 1, read from Slot 0

// Read key: where processing/consumption reads from
function _tqReadKey(uint24 lvl) internal view returns (uint24) {
    return ticketWriteSlot == 0 ? lvl | TICKET_SLOT_BIT : lvl;
}

// Far-future key: independent of double-buffer
function _tqFarFutureKey(uint24 lvl) internal pure returns (uint24) {
    return lvl | TICKET_FAR_FUTURE_BIT;
}
```

### Near-Future vs Far-Future Routing

All three queue helpers (`_queueTickets` GS:537, `_queueTicketsScaled` GS:565, `_queueTicketRange` GS:611) implement the same routing logic:

```solidity
bool isFarFuture = targetLevel > level + 6;          // GS:544, GS:572, GS:621
if (isFarFuture && rngLockedFlag && !phaseTransitionActive) revert RngLocked();
uint24 wk = isFarFuture ? _tqFarFutureKey(targetLevel) : _tqWriteKey(targetLevel);
```

- Near-future (targetLevel <= level + 6): routes to write buffer via `_tqWriteKey`
- Far-future (targetLevel > level + 6): routes to FF key via `_tqFarFutureKey`
- Far-future writes blocked during VRF commitment window (rngLockedFlag=true, phaseTransitionActive=false)
- Exception: advanceGame internal writes set phaseTransitionActive=true, exempting vault perpetual tickets

### Queue Swap and Prize Pool Freeze

```
_swapTicketSlot(purchaseLevel) -- GS:709-714
  1. Verifies read buffer is drained: ticketQueue[_tqReadKey(purchaseLevel)].length == 0
  2. Flips: ticketWriteSlot ^= 1
  3. Resets: ticketsFullyProcessed = false

_swapAndFreeze(purchaseLevel) -- GS:719-725
  1. Calls _swapTicketSlot
  2. If not already frozen: sets prizePoolFrozen = true, zeros prizePoolPendingPacked
  3. If already frozen: accumulators keep growing (multi-day jackpot)
```

### Trigger Conditions for Swap

| Trigger | Location | When |
|---------|----------|------|
| `_swapAndFreeze(purchaseLevel)` | AM:233 | Daily RNG request path (new-day advanceGame, after read slot fully processed) |
| `_swapTicketSlot(purchaseLevel_)` | AM:720 | Mid-day lootbox RNG request path (`requestLootboxRng`), only when `ticketsFullyProcessed && ticketQueue[wk].length > 0` |

### Complete Ticket Creation Entry Point Enumeration

**External functions (permissionless, user-callable):**

| # | Function | Module | Queue Call | Location |
|---|----------|--------|-----------|----------|
| 1 | `purchase()` | MintModule | `_queueTicketsScaled` | MM:1038 |
| 2 | `purchaseCoin()` | MintModule | `_queueTicketsScaled` (same `_purchaseFor`) | MM:1038 |
| 3 | `purchaseWhaleBundle()` | WhaleModule | `_queueTickets` x100 loop | WM:270 |
| 4 | `purchaseLazyPass()` | WhaleModule | `_queueTickets` (via `_activate10LevelPass` at GS:1070 using `_queueTicketRange`) + bonus tickets (WM:425) | GS:1070, WM:425 |
| 5 | `purchaseDeityPass()` | WhaleModule | `_queueTickets` x100 loop | WM:540 |
| 6 | `openLootBox()` / `openBurnieLootBox()` | LootboxModule | `_queueTicketsScaled` (LM:1000) + optional `_activateWhalePass` -> `_queueTickets` x100 loop (LM:1129) | LM:1000, LM:1129 |
| 7 | `claimWhalePass()` | EndgameModule | `_queueTicketRange` | EM:548 |
| 8 | `claimDecimatorJackpot()` | DecimatorModule | `_queueTickets` (via `_processAutoRebuy` DM:391) | DM:391 |

**Internal paths (within advanceGame or jackpot processing):**

| # | Path | Module | Queue Call | Location |
|---|------|--------|-----------|----------|
| 9 | Vault perpetual tickets | AdvanceModule | `_queueTickets` x2 (SDGNRS + VAULT) | AM:1227-1232 |
| 10 | Constructor pre-queue | DegenerusGame | `_queueTickets` x200 (levels 1-100 x 2 addresses) | DG:250-251 |
| 11 | Daily jackpot auto-rebuy | JackpotModule | `_processAutoRebuy` -> `_queueTickets` | JM:1008 |
| 12 | Earlybird lootbox jackpot | JackpotModule | `_queueTickets` (winners get tickets at baseLevel + levelOffset) | JM:848 |
| 13 | Daily ticket distribution | JackpotModule | `_distributeTicketJackpot` -> `_queueTickets` | JM:1209 |
| 14 | Endgame auto-rebuy | EndgameModule | `_queueTickets` (via auto-rebuy in `_addClaimableEth`) | EM:286 |
| 15 | Decimator auto-rebuy | DecimatorModule | `_queueTickets` (via `_processAutoRebuy`) | DM:391 |

### Ticket Count Determination by Path

| Path | Ticket Count | Target Level | Notes |
|------|-------------|--------------|-------|
| purchase/purchaseCoin | `adjustedQuantity` (scaled) | `level + 1` | Price-derived, uses TICKET_SCALE=100 |
| purchaseWhaleBundle | 40/lvl bonus (passLevel to WHALE_BONUS_END_LEVEL), 2/lvl rest | passLevel to passLevel+99 | Fixed per-level, multiplied by quantity |
| purchaseLazyPass | 4/lvl for 10 levels + variable bonus tickets | level+1 to level+10 | Bonus from flat-price overpayment at early levels |
| purchaseDeityPass | 40/lvl bonus, 2/lvl rest (whale-equivalent) | ticketStartLevel to ticketStartLevel+99 | Same pattern as whale bundle |
| openLootBox | `futureTickets` (scaled) | `targetLevel` (from lootbox resolution) | Can be well beyond level+6 (far-future) |
| claimWhalePass | `halfPasses` per level x 100 levels | level+1 to level+100 | Deferred from large lootbox wins |
| Auto-rebuy (all modules) | `calc.ticketCount` (price-derived) | level + 1 to level + 4 | Range from `(entropy & 3) + 1` in PayoutUtils:54-58 |
| Vault perpetual | 16 per address | purchaseLevel + 99 | Fixed, always far-future, phaseTransitionActive exemption |
| Constructor | 16 per address per level | levels 1-100 | One-time at deploy |
| Earlybird jackpot | `perWinnerEth / ticketPrice` | baseLevel + levelOffset (0-4) | RNG-dependent count |
| Ticket distribution | `ticketUnits / cap` per winner | lvl + 1 | Distributed across trait buckets |

### rngLockedFlag Behavior by Path

| Path | rngLockedFlag Guard | Location | Notes |
|------|-------------------|----------|-------|
| All three queue helpers | `isFarFuture && rngLockedFlag && !phaseTransitionActive -> revert` | GS:545, GS:573, GS:622 | Only blocks far-future writes |
| purchaseDeityPass | Own `rngLockedFlag` check: `if (rngLockedFlag) revert RngLocked()` | WM:475 | Blocks ALL deity pass purchases during RNG window |
| purchase / purchaseCoin | No own rngLockedFlag check | MintModule | Relies on queue helper guard for FF writes only |
| purchaseWhaleBundle / purchaseLazyPass | WhaleModule does not check rngLockedFlag on these paths | WhaleModule | Relies on queue helper guard |
| claimWhalePass | No own check | EM:530 | Relies on queue helper guard |
| openLootBox | No own check | LootboxModule | Relies on queue helper guard |
| claimDecimatorJackpot | No own check | DecimatorModule | Auto-rebuy targets level+1 to level+4 (always near-future) |
| Vault perpetual | phaseTransitionActive=true exemption | AM:1227 | Deterministic, same transaction as jackpot |

### prizePoolFrozen Behavior

prizePoolFrozen does NOT affect ticket creation. It redirects pool contributions:

| Condition | Pool Write |
|-----------|-----------|
| `!prizePoolFrozen` | Direct write to `prizePoolsPacked` (next/future) |
| `prizePoolFrozen` | Write to `prizePoolPendingPacked` (accumulated, applied at unfreeze) |

Checked at: WM:298 (whaleBundle), WM:434 (lazyPass), WM:551 (deityPass), MM:779 (purchase), DegeneretteModule:558/685 (degenerette).

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Ticket queue tracing | Custom static analysis tools | Systematic grep + manual code reading | Contract uses delegatecall patterns that confuse automated analyzers; manual trace with file:line is the gold standard for audit |
| Storage slot verification | Manual counting | `forge inspect DegenerusGame storage-layout` | Compiler-authoritative slot assignments; manual counting is error-prone with packed structs |
| Discrepancy detection | Relying on prior audit docs | Independent code reading, then cross-reference | v3.8 has CONFIRMED ERRORS (STATE.md); every prior claim must be independently verified |

## Common Pitfalls

### Pitfall 1: Trusting Prior Audit Documentation
**What goes wrong:** Copying claims from v3.8/v3.9 without verifying against current code
**Why it happens:** v3.9 Phase 77 implemented a combined pool approach that was later reverted (commit 2bf830a2). The v3.9 RNG commitment window proof describes the combined pool behavior but the code now uses FF-only.
**How to avoid:** Every claim must have a current file:line citation. "Prior audit says X" is not evidence -- "code at JM:2543 does Y" is evidence.
**Warning signs:** Any claim about `_awardFarFutureCoinJackpot` reading from both read buffer and FF key is stale.

### Pitfall 2: Missing the _tqWriteKey in sampleFarFutureTickets
**What goes wrong:** Failing to check view functions for queue key usage
**Why it happens:** View functions don't affect state, so they're often skipped in security audits
**How to avoid:** Include view functions in the enumeration -- they affect off-chain consumers and UI correctness
**Warning signs:** `sampleFarFutureTickets` (DG:2681) uses `_tqWriteKey`, not `_tqFarFutureKey` -- inconsistent with `_awardFarFutureCoinJackpot`

### Pitfall 3: Conflating prizePoolFrozen with Ticket Creation
**What goes wrong:** Claiming prizePoolFrozen affects ticket queuing
**Why it happens:** Both are mentioned in the same context (daily RNG path) and `_swapAndFreeze` does both
**How to avoid:** Trace separately -- `_swapAndFreeze` swaps the ticket buffer AND freezes pools, but these are independent effects. Pool freeze affects ETH routing, not ticket queuing.

### Pitfall 4: Missing the phaseTransitionActive Exemption
**What goes wrong:** Claiming rngLockedFlag blocks all far-future writes during VRF window
**Why it happens:** The guard checks `!phaseTransitionActive`, which is true for external callers but false during advanceGame phase transitions
**How to avoid:** Document the exemption explicitly; verify it only applies to vault perpetual tickets (deterministic, same-transaction)

### Pitfall 5: Treating _queueLootboxTickets as a Separate Path
**What goes wrong:** Listing `_queueLootboxTickets` as a 4th queue helper with different behavior
**Why it happens:** It exists as a separate function (GS:647-654)
**How to avoid:** Note that `_queueLootboxTickets` is a thin wrapper that delegates to `_queueTicketsScaled` -- same routing, same guards. Only one caller (LM:1000 is already covered by `_queueTicketsScaled`).

### Pitfall 6: Incorrect ticketsOwedPacked Overflow Analysis
**What goes wrong:** Assuming unchecked addition of owed tickets can overflow uint32
**Why it happens:** `_queueTickets` uses `unchecked { owed += quantity; }` at GS:554
**How to avoid:** Note that practical ticket counts are bounded by ETH supply and ticket prices, making uint32 overflow infeasible. The NatSpec at GS:533 says "Caps at uint32 max to prevent overflow" but the code uses unchecked -- this is a potential comment correctness issue to flag.

## Known Discrepancies to Flag (Pre-identified)

These should be verified and documented as [DISCREPANCY] or [NEW FINDING] during plan execution:

1. **v3.9 RNG commitment window proof (audit/v3.9-rng-commitment-window-proof.md) Section 2**: Describes backward trace with `readQueue = ticketQueue[_tqReadKey(candidate)]` and `ffQueue = ticketQueue[_tqFarFutureKey(candidate)]` combined pool. Current code at JM:2543 reads ONLY from `_tqFarFutureKey(candidate)`. [DISCREPANCY with v3.9 Phase 79 proof]

2. **sampleFarFutureTickets (DG:2681)**: Uses `_tqWriteKey(candidate)` to sample far-future tickets. After the FF key space was introduced, this view function was not updated. It reads from the write buffer, not from the FF key space where far-future tickets now live. [NEW FINDING - view function correctness]

3. **Phase 72 research (v3.8)**: Describes `_awardFarFutureCoinJackpot` reading from `_tqWriteKey` at "JackpotModule:2544". This was the pre-fix code. Must be flagged as historical context only. [DISCREPANCY with v3.8 Phase 72 research -- now outdated]

4. **NatSpec at GS:533**: Says "Caps at uint32 max to prevent overflow" but `_queueTickets` uses unchecked arithmetic at GS:554. [Potential DISCREPANCY - comment vs code]

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Foundry (forge) + Hardhat |
| Config file | `foundry.toml` |
| Quick run command | `forge test --match-contract <TestName> -vvv` |
| Full suite command | `forge test` |

### Phase Requirements -> Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| TKT-01 | All external ticket creation functions identified | manual audit | N/A (audit doc review) | N/A |
| TKT-02 | Ticket count/level/key selection documented | manual audit | N/A (audit doc review) | N/A |
| TKT-03 | rngLockedFlag/prizePoolFrozen behavior | manual audit | N/A (audit doc review) | N/A |
| TKT-04 | All queue callers enumerated | manual audit | N/A (code trace) | N/A |
| TKT-05 | Double-buffer formulas documented | manual audit + existing test | `forge test --match-contract QueueDoubleBuffer -vvv` | Yes (test/fuzz/QueueDoubleBuffer.t.sol) |
| TKT-06 | Swap trigger conditions documented | manual audit + existing test | `forge test --match-contract PrizePoolFreeze -vvv` | Yes (test/fuzz/PrizePoolFreeze.t.sol) |
| DSC-01 | Discrepancies flagged | manual audit | N/A (doc review) | N/A |
| DSC-02 | New findings flagged | manual audit | N/A (doc review) | N/A |

### Sampling Rate
- **Per task commit:** `forge test --match-contract QueueDoubleBuffer -vvv` (verify no regression)
- **Per wave merge:** `forge test` (full suite)
- **Phase gate:** All existing Foundry tests pass before /gsd:verify-work

### Wave 0 Gaps
None -- this is an audit-only phase (no code changes). Existing test infrastructure covers double-buffer and prize pool freeze mechanics. The deliverable is an audit document, not code.

## Code Examples

### Core Queue Helper: _queueTickets (GS:537-558)
```solidity
// Source: contracts/storage/DegenerusGameStorage.sol:537-558
function _queueTickets(
    address buyer,
    uint24 targetLevel,
    uint32 quantity
) internal {
    if (quantity == 0) return;
    emit TicketsQueued(buyer, targetLevel, quantity);
    bool isFarFuture = targetLevel > level + 6;
    if (isFarFuture && rngLockedFlag && !phaseTransitionActive) revert RngLocked();
    uint24 wk = isFarFuture ? _tqFarFutureKey(targetLevel) : _tqWriteKey(targetLevel);
    uint40 packed = ticketsOwedPacked[wk][buyer];
    uint32 owed = uint32(packed >> 8);
    uint8 rem = uint8(packed);
    if (owed == 0 && rem == 0) {
        ticketQueue[wk].push(buyer);
    }
    unchecked {
        owed += quantity;
    }
    ticketsOwedPacked[wk][buyer] =
        (uint40(owed) << 8) | uint40(rem);
}
```

### Key Encoding (GS:686-700)
```solidity
// Source: contracts/storage/DegenerusGameStorage.sol:686-700
function _tqWriteKey(uint24 lvl) internal view returns (uint24) {
    return ticketWriteSlot != 0 ? lvl | TICKET_SLOT_BIT : lvl;
}
function _tqReadKey(uint24 lvl) internal view returns (uint24) {
    return ticketWriteSlot == 0 ? lvl | TICKET_SLOT_BIT : lvl;
}
function _tqFarFutureKey(uint24 lvl) internal pure returns (uint24) {
    return lvl | TICKET_FAR_FUTURE_BIT;
}
```

### Swap Mechanics (GS:709-735)
```solidity
// Source: contracts/storage/DegenerusGameStorage.sol:709-735
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
```

### Current _awardFarFutureCoinJackpot (JM:2521-2560) -- FF-key only
```solidity
// Source: contracts/modules/DegenerusGameJackpotModule.sol:2543
// NOTE: This reads ONLY from _tqFarFutureKey, NOT combined pool.
// The combined pool (read buffer + FF key) from Phase 77 was reverted in 2bf830a2.
address[] storage queue = ticketQueue[_tqFarFutureKey(candidate)];
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `_awardFarFutureCoinJackpot` reads from `_tqWriteKey` | Reads from `_tqFarFutureKey` only | v3.9 Phase 77 + commit 2bf830a2 | TQ-01 fixed; write buffer no longer readable by jackpot draw |
| No far-future key space | `TICKET_FAR_FUTURE_BIT = 1 << 22` (third key space) | v3.9 Phase 74 | Tickets targeting > level+6 now routed to independent key space |
| No rngLockedFlag guard on queue helpers | Guard at GS:545/573/622 | v3.9 Phase 75 | Far-future writes blocked during VRF commitment window |
| Single-buffer queue | Double-buffer + FF key (three key spaces total) | v3.9 Phases 74-77 | Complete isolation between write/read/far-future |

**Prior approach (v3.8 Phase 72):** `_awardFarFutureCoinJackpot` read from `_tqWriteKey` -- confirmed vulnerability TQ-01 (MEDIUM). Fixed in v3.9.

**Intermediate approach (v3.9 Phase 77):** Combined pool reading from `_tqReadKey` + `_tqFarFutureKey`. Reverted in commit `2bf830a2` to FF-only read.

**Current approach:** FF-only read. `_awardFarFutureCoinJackpot` at JM:2543 reads exclusively from `_tqFarFutureKey(candidate)`.

## Open Questions

1. **Why was the combined pool reverted?**
   - What we know: Commit `2bf830a2` message says "jackpot FF-only read" -- it reverted the combined pool
   - What's unclear: Whether this was intentional simplification or bug fix. The v3.9 Phase 79 RNG proof was written for the combined pool version.
   - Recommendation: Document the current FF-only behavior and flag the stale v3.9 proof as [DISCREPANCY]. The FF-only approach is simpler and still eliminates TQ-01.

2. **sampleFarFutureTickets correctness**
   - What we know: Uses `_tqWriteKey` at DG:2681, which reads the current write buffer. After v3.9, far-future tickets go to `_tqFarFutureKey` space.
   - What's unclear: Whether this view function is used by any on-chain consumer or only off-chain UIs.
   - Recommendation: Flag as [NEW FINDING] (INFO severity) -- view function returns incorrect data for far-future ticket sampling. The function should use `_tqFarFutureKey` or sample from both key spaces.

3. **_queueTickets unchecked overflow**
   - What we know: GS:554 uses `unchecked { owed += quantity; }` but NatSpec at GS:533 says "Caps at uint32 max"
   - What's unclear: Whether the cap claim refers to the practical impossibility of overflow or an explicit check that was removed
   - Recommendation: Flag as potential comment correctness issue

## Sources

### Primary (HIGH confidence)
- `contracts/storage/DegenerusGameStorage.sol` -- all queue helpers, key encoding, swap mechanics (GS:430-735)
- `contracts/modules/DegenerusGameJackpotModule.sol` -- `_awardFarFutureCoinJackpot` current code (JM:2521-2606)
- `contracts/modules/DegenerusGameMintModule.sol` -- purchase path ticket creation (MM:1034-1038)
- `contracts/modules/DegenerusGameWhaleModule.sol` -- whale/lazy/deity pass ticket creation
- `contracts/modules/DegenerusGameLootboxModule.sol` -- lootbox ticket creation (LM:1000, LM:1129)
- `contracts/modules/DegenerusGameAdvanceModule.sol` -- vault perpetual tickets (AM:1227-1232), swap triggers (AM:233, AM:720)
- `contracts/modules/DegenerusGameDecimatorModule.sol` -- auto-rebuy ticket creation (DM:391)
- `contracts/modules/DegenerusGameEndgameModule.sol` -- whale pass claim (EM:548), auto-rebuy (EM:286)
- `contracts/modules/DegenerusGamePayoutUtils.sol` -- auto-rebuy target level calc (PU:54-58)
- `contracts/DegenerusGame.sol` -- constructor pre-queue (DG:250-251), sampleFarFutureTickets (DG:2669-2705)
- git diff `7dd5002a..2bf830a2` -- confirmed revert of combined pool to FF-only

### Secondary (MEDIUM confidence)
- `.planning/milestones/v3.8-phases/72-ticket-queue-deep-dive-pattern-scan/72-RESEARCH.md` -- Phase 72 research (pre-fix TQ-01 analysis)
- `audit/v3.9-rng-commitment-window-proof.md` -- v3.9 commitment window proof (contains stale combined pool claims)
- `.planning/milestones/v3.9-phases/77-jackpot-combined-pool-tq-01-fix/77-01-SUMMARY.md` -- Phase 77 fix summary

### Tertiary (LOW confidence)
- None

## Metadata

**Confidence breakdown:**
- Entry point enumeration: HIGH -- grep across all contracts, cross-verified with prior audits
- Double-buffer mechanics: HIGH -- code directly readable, verified against three separate sources
- Discrepancy identification: HIGH -- git diff confirms combined pool revert; current code directly inspected
- Queue helper guards: HIGH -- all three helpers read and guard logic verified line-by-line

**Research date:** 2026-03-23
**Valid until:** Indefinite (audit of immutable contract code)

## Project Constraints (from CLAUDE.md)

From global CLAUDE.md:
- **Self-check before delivering results** -- after completing any substantial task, internally review for gaps, stale references, cascading changes

From project memory:
- **Only read contracts from `contracts/` directory** -- stale copies exist elsewhere
- **Present fix and wait for explicit approval before editing code** -- audit-only phase, no code changes
- **Never push contract changes without explicit user review** -- N/A for audit-only phase
- **NEVER commit contracts/ or test/ changes without explicit user approval** -- N/A for audit-only phase
- **Every RNG audit must trace BACKWARD from each consumer** -- applicable to verifying RNG guards on ticket queue writes
- **Every RNG audit must check what player-controllable state can change between VRF request and fulfillment** -- applicable to verifying rngLockedFlag guards

From STATE.md:
- **v3.8 commitment window inventory has CONFIRMED ERRORS** -- all prior audit prose must be treated as unverified
- **DSC-01/DSC-02 are cross-cutting** -- apply to all 6 phases, not standalone
