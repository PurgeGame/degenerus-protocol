# Phase 15: Ticket Creation & Mid-Day RNG Deep-Dive - Research

**Researched:** 2026-03-14
**Domain:** Ticket creation lifecycle, mid-day VRF entropy, coinflip lock timing -- smart contract security audit
**Confidence:** HIGH

## Summary

Phase 15 is the final audit phase requiring a focused end-to-end trace of ticket creation through trait assignment, with particular attention to the mid-day `requestLootboxRng` flow and coinflip lock timing. Unlike Phases 12-14 which built inventories and broad window analyses, this phase drills into four specific flows where RNG entropy determines ticket outcomes, producing SAFE/EXPLOITABLE verdicts for each.

The critical flows are: (1) ticket creation via `_queueTickets`/`_queueTicketsScaled` into the write buffer, buffered by the double-buffer mechanism, then trait assignment via `processTicketBatch` using `lastLootboxRngWord` as entropy through `_raritySymbolBatch`; (2) the mid-day `requestLootboxRng` to `_swapTicketSlot` to VRF callback to `advanceGame` drain sequence; (3) whether knowing `lastLootboxRngWord` (publicly readable) enables trait or outcome manipulation; (4) the `_coinflipLockedDuringTransition` function's narrow scope (only fires on BAF-eligible levels with `lastPurchaseDay && rngLocked && !inJackpotPhase && purchaseLevel % 10 == 0`) and whether gaps exist versus RNG-sensitive windows.

Much of the foundational analysis exists in prior phases. Phase 12 (Plan 03) documented the mid-day ticket flow in `v1.2-rng-data-flow.md` Section 3. Phase 14 (Plan 01) analyzed L4 (`processTicketBatch`) as a consumption point and rated it BLOCKED. Phase 14 (Plan 02) confirmed `processTicketBatch` during jackpot uses the piggybacked daily VRF word set atomically. Phase 15's job is to weave these into a single coherent trace, verify no gaps, and produce explicit verdicts for each TICKET requirement.

**Primary recommendation:** Structure as 2 plans: (1) end-to-end ticket creation trace covering TICKET-01 and TICKET-03, (2) mid-day RNG flow and coinflip lock analysis covering TICKET-02 and TICKET-04.

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| TICKET-01 | Full trace of ticket creation -> buffer assignment -> trait assignment with entropy source at each step | Contract code traced: `_queueTickets` (Storage:545) -> write buffer via `_tqWriteKey` -> `_swapTicketSlot` (Storage:732) -> `processTicketBatch` (JackpotModule:1949) reads `lastLootboxRngWord` at :1975 -> `_processOneTicketEntry` -> `_generateTicketBatch` -> `_raritySymbolBatch` (JackpotModule:2187) uses LCG-based PRNG seeded from VRF word |
| TICKET-02 | Mid-day `requestLootboxRng` -> buffer swap -> `processTicketBatch` flow verified for manipulation resistance | Mid-day flow traced at AdvanceModule:673-735 (request) -> :1326-1345 (callback, lootbox path) -> :155-196 (advanceGame mid-day drain). Double-buffer swap atomic with VRF request. VRF word written to index then read at drain time. |
| TICKET-03 | Verify no trait/outcome influenced when `lastLootboxRngWord` known | `lastLootboxRngWord` is publicly readable (storage slot). Trait assignment uses LCG seeded from `(baseKey + groupIdx) ^ entropyWord` where baseKey encodes level, queueIdx, player -- per-entry deterministic. Knowing the word reveals future trait assignments for known queue composition, but queue composition in read buffer is frozen. |
| TICKET-04 | Coinflip lock timing verified -- `_coinflipLockedDuringTransition` windows align with RNG-sensitive periods | `_coinflipLockedDuringTransition` (BurnieCoinflip:1032-1044) only locks when ALL five conditions hold: `!inJackpotPhase && !gameOver && lastPurchaseDay && rngLocked && purchaseLevel % 10 == 0`. Coinflip claims separately blocked by `rngLocked()` check. Gap analysis needed for non-x10 levels and jackpot phase. |
</phase_requirements>

## Standard Stack

This phase produces audit analysis documents, not code. No library stack is needed.

### Analysis Tools
| Tool | Purpose | Why Standard |
|------|---------|--------------|
| Contract source reading | Trace ticket creation, buffer swap, trait assignment, coinflip lock code paths | Primary evidence source |
| Phase 12 data flow doc | Authoritative mid-day ticket flow diagram (Section 3) and consumption points | Verified inventory from prior phase |
| Phase 14 manipulation windows | L4 window analysis, inter-block jackpot gap analysis | Contains existing verdicts to extend |
| v1.2-rng-storage-variables.md | Variable lifecycles for lastLootboxRngWord, ticketWriteSlot | Storage layout reference |

## Architecture Patterns

### Analysis Structure

The output document should cover all 4 TICKET requirements in a single audit document:

```
audit/v1.2-ticket-rng-deep-dive.md
  Section 1: Ticket Creation End-to-End Trace (TICKET-01)
    1a: Purchase -> _queueTickets -> write buffer
    1b: _swapTicketSlot -> read buffer activation
    1c: processTicketBatch -> _processOneTicketEntry -> _raritySymbolBatch
    1d: Entropy source identification at each step
  Section 2: Mid-Day RNG Flow (TICKET-02)
    2a: requestLootboxRng trigger conditions and buffer swap
    2b: VRF callback routing (lootbox path)
    2c: advanceGame mid-day drain path
    2d: Manipulation resistance analysis with explicit reasoning
  Section 3: lastLootboxRngWord Observability (TICKET-03)
    3a: Who can read lastLootboxRngWord and when
    3b: What information it reveals about trait assignment
    3c: Whether frozen read-buffer prevents exploitation
    3d: SAFE/EXPLOITABLE verdict with evidence
  Section 4: Coinflip Lock Timing (TICKET-04)
    4a: _coinflipLockedDuringTransition condition analysis
    4b: RNG-sensitive period enumeration
    4c: Gap analysis (periods where coinflip is unlocked but RNG is sensitive)
    4d: Alignment verdict
```

### Key Data Structures

**Double-Buffer Encoding:**
```
ticketWriteSlot: uint8 (0 or 1)
TICKET_SLOT_BIT: bit 23 of level key

_tqWriteKey(level): ticketWriteSlot != 0 ? level | TICKET_SLOT_BIT : level
_tqReadKey(level):  ticketWriteSlot == 0 ? level | TICKET_SLOT_BIT : level

ticketQueue[key]: address[] -- list of players with tickets at this key
ticketsOwedPacked[key][player]: uint40 -- (uint32 owed << 8) | uint8 remainder
```

**Trait Assignment Entropy Chain:**
```
lastLootboxRngWord (VRF-derived, set by _finalizeLootboxRng or mid-day drain)
  -> processTicketBatch reads at JackpotModule:1975
  -> passed to _processOneTicketEntry as `entropy`
  -> passed to _generateTicketBatch -> _raritySymbolBatch
  -> Per-ticket: seed = (baseKey + groupIdx) ^ entropyWord
     baseKey = (level << 224) | (queueIdx << 192) | (player << 32)
     LCG stepping: s = s * TICKET_LCG_MULT + 1
     traitId = DegenerusTraitUtils.traitFromWord(s) + (quadrantOffset << 6)
```

**Coinflip Lock Conditions (5-way AND):**
```
_coinflipLockedDuringTransition():
  !inJackpotPhase     -- only during purchase phase
  && !gameOver         -- not after game ends
  && lastPurchaseDay   -- only on last purchase day (transition day)
  && rngLocked         -- only when VRF is in-flight
  && purchaseLevel % 10 == 0  -- only at BAF-eligible levels
```

### Key Contract Locations

| Component | File | Lines | Purpose |
|-----------|------|-------|---------|
| `_queueTickets` | Storage:545-571 | Queue tickets to write buffer | Entry point for ticket creation |
| `_queueTicketsScaled` | Storage:578-627 | Fractional ticket queuing | Handles remainder accumulation |
| `_swapTicketSlot` | Storage:732-737 | Toggle double-buffer, assert read drained | Buffer swap mechanism |
| `_swapAndFreeze` | Storage:742-748 | Swap + freeze pool (daily path) | Combined swap for daily VRF |
| `requestLootboxRng` | AdvanceModule:673-735 | Mid-day VRF request with buffer swap | Mid-day entry point |
| `rawFulfillRandomWords` | AdvanceModule:1326-1345 | VRF callback routing | Word storage (daily vs lootbox path) |
| `advanceGame` mid-day | AdvanceModule:155-196 | Mid-day ticket drain path | Reads VRF word, runs processTicketBatch |
| `processTicketBatch` | JackpotModule:1949-2010 | Batch trait assignment | Reads lastLootboxRngWord, iterates queue |
| `_processOneTicketEntry` | JackpotModule:2044-2107 | Single player ticket processing | Trait generation per player |
| `_raritySymbolBatch` | JackpotModule:2187-2280 | LCG-based trait generation | Assembly-optimized batch writes |
| `_coinflipLockedDuringTransition` | BurnieCoinflip:1032-1044 | Coinflip deposit lock check | 5-condition guard |
| `_depositCoinflip` | BurnieCoinflip:248-258 | Deposit with lock check | Only deposit path checks transition lock |

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Mid-day flow trace | Re-derive from contracts | Phase 12 data flow Section 3 (v1.2-rng-data-flow.md) | Complete lifecycle diagram already exists |
| L4 window analysis | Re-analyze from scratch | Phase 14 L4 analysis (v1.2-manipulation-windows.md Section 1b) | BLOCKED verdict with double-buffer evidence |
| processTicketBatch entropy source during jackpot | Re-trace | Phase 14 Open Question 3 resolution | Confirmed: uses piggybacked daily VRF word |
| Entry point callability during lock | Re-enumerate | Phase 12 cross-reference matrix (v1.2-rng-data-flow.md Section 5) | 27 entry points fully mapped |

## Common Pitfalls

### Pitfall 1: Confusing Write Buffer with Read Buffer for Ticket Processing
**What goes wrong:** Claiming tickets in the write buffer can be manipulated, when actually processTicketBatch operates on the READ buffer which was frozen at swap time.
**Why it happens:** The double-buffer has two keys computed from `ticketWriteSlot`, and it is easy to confuse which buffer is being modified vs consumed.
**How to avoid:** Always trace through `_tqWriteKey` vs `_tqReadKey` to confirm which buffer a function operates on. `_queueTickets` uses `_tqWriteKey`; `processTicketBatch` uses `_tqReadKey`.
**Warning signs:** Analysis claims "new purchases affect trait assignment outcomes" without distinguishing buffer slots.

### Pitfall 2: Assuming lastLootboxRngWord is Private
**What goes wrong:** Claiming lastLootboxRngWord cannot be observed, when it is a public storage variable readable by anyone.
**Why it happens:** Internal visibility in Solidity still means it is in contract storage, readable via `eth_getStorageAt`.
**How to avoid:** Explicitly acknowledge observability and reason about whether knowing the value enables exploitation (it should not, because the read buffer is frozen).
**Warning signs:** SAFE verdict based on "attacker cannot know the entropy" rather than "knowing the entropy does not help."

### Pitfall 3: Missing the Two lastLootboxRngWord Write Paths
**What goes wrong:** Only tracing the mid-day drain path (AdvanceModule:166) and missing the piggyback write path (_finalizeLootboxRng at AdvanceModule:789).
**Why it happens:** There are two independent code paths that update lastLootboxRngWord.
**How to avoid:** Trace both write sites: AdvanceModule:166 (mid-day drain) and AdvanceModule:789 (piggyback from daily VRF processing).
**Warning signs:** Analysis says "lastLootboxRngWord is only set during mid-day drain."

### Pitfall 4: Conflating _coinflipLockedDuringTransition with rngLockedFlag
**What goes wrong:** Assuming `_coinflipLockedDuringTransition` provides the same protection as `rngLockedFlag`, when it is much narrower (only on x10 levels, only during purchase phase last day).
**Why it happens:** Both relate to "locking coinflip" but serve different purposes.
**How to avoid:** Separately analyze: (a) coinflip CLAIM functions check `rngLocked()` directly (4 functions in BurnieCoinflip:336/347/357/367); (b) coinflip DEPOSIT function checks `_coinflipLockedDuringTransition()` (BurnieCoinflip:258). These are independent guards for different attack vectors.
**Warning signs:** Analysis treats deposit lock and claim lock as the same mechanism.

### Pitfall 5: Ignoring the rollSalt Determinism in Trait Assignment
**What goes wrong:** Claiming trait assignment is "random" when it is actually fully deterministic given lastLootboxRngWord and the queue composition.
**Why it happens:** The LCG-based PRNG looks random but the seed is derived from known values.
**How to avoid:** Recognize that `seed = (baseKey + groupIdx) ^ entropyWord` where baseKey encodes level, queueIdx, and player -- all knowable. The entropy comes solely from `entropyWord` (= lastLootboxRngWord). This is BY DESIGN: determinism enables verification, and the double-buffer prevents the adversary from changing what the entropy indexes INTO.
**Warning signs:** Analysis fails to acknowledge deterministic trait assignment and its security implications.

## Code Examples

### Ticket Creation Entry Point (Storage:545-570)
```solidity
// Source: contracts/storage/DegenerusGameStorage.sol:545
function _queueTickets(address buyer, uint24 targetLevel, uint32 quantity) internal {
    if (quantity == 0) return;
    uint24 wk = _tqWriteKey(targetLevel);  // WRITE buffer key
    uint40 packed = ticketsOwedPacked[wk][buyer];
    uint32 owed = uint32(packed >> 8);
    uint8 rem = uint8(packed);
    if (owed == 0 && rem == 0) {
        ticketQueue[wk].push(buyer);  // Add to queue only on first ticket
    }
    // ... cap at uint32 max, store packed
}
```

### Buffer Swap (Storage:732-737)
```solidity
// Source: contracts/storage/DegenerusGameStorage.sol:732
function _swapTicketSlot(uint24 purchaseLevel) internal {
    uint24 rk = _tqReadKey(purchaseLevel);
    if (ticketQueue[rk].length != 0) revert E();  // Read buffer must be drained
    ticketWriteSlot ^= 1;                          // Toggle: write becomes read
    ticketsFullyProcessed = false;                  // New read buffer needs processing
}
```

### Mid-Day VRF Request with Buffer Swap (AdvanceModule:708-735)
```solidity
// Source: contracts/modules/DegenerusGameAdvanceModule.sol:708-715
// Freeze ticket buffer: swap write->read so tickets purchased after
// VRF delivery can't be resolved by this word.
uint24 wk = _tqWriteKey(purchaseLevel_);
if (ticketQueue[wk].length > 0 && ticketsFullyProcessed) {
    _swapTicketSlot(purchaseLevel_);      // Atomic: write->read, read->write
    midDayTicketRngPending = true;        // Flag: drain after VRF arrives
}
// VRF request sent at :720 with VRF_MIDDAY_CONFIRMATIONS = 3
```

### Mid-Day Drain Path (AdvanceModule:158-183)
```solidity
// Source: contracts/modules/DegenerusGameAdvanceModule.sol:158-183
if (day == dailyIdx) {  // Same-day path
    if (!ticketsFullyProcessed) {
        if (midDayTicketRngPending) {
            uint256 word = lootboxRngWordByIndex[lootboxRngIndex - 1];
            if (word == 0) revert NotTimeYet();  // VRF not arrived yet
            lastLootboxRngWord = word;            // Update entropy source
        }
        // _runProcessTicketBatch reads lastLootboxRngWord via processTicketBatch
        uint24 rk = _tqReadKey(purchaseLevel);
        if (ticketQueue[rk].length > 0) {
            (bool ticketWorked, bool ticketsFinished) = _runProcessTicketBatch(purchaseLevel);
            // ... returns after work, or marks ticketsFullyProcessed = true
        }
    }
}
```

### Trait Assignment Entropy (JackpotModule:1975, 2187-2213)
```solidity
// Source: contracts/modules/DegenerusGameJackpotModule.sol:1975
uint256 entropy = lastLootboxRngWord;  // Single entropy source for entire batch

// Source: JackpotModule:2209-2224 (_raritySymbolBatch)
uint256 seed;
unchecked { seed = (baseKey + groupIdx) ^ entropyWord; }
uint64 s = uint64(seed) | 1;  // Ensure odd for full LCG period
// LCG stepping per ticket:
s = s * TICKET_LCG_MULT + 1;
uint8 traitId = DegenerusTraitUtils.traitFromWord(s) + (uint8(i & 3) << 6);
```

### Coinflip Lock Check (BurnieCoinflip:1032-1044)
```solidity
// Source: contracts/BurnieCoinflip.sol:1032-1044
function _coinflipLockedDuringTransition() private view returns (bool locked) {
    (uint24 purchaseLevel_, bool inJackpotPhase, bool lastPurchaseDay_, bool rngLocked_,)
        = degenerusGame.purchaseInfo();
    locked = (!inJackpotPhase) && !degenerusGame.gameOver()
        && lastPurchaseDay_ && rngLocked_
        && (purchaseLevel_ % 10 == 0);
}
```

## State of the Art

### VRF Confirmation Counts
| Path | Confirmations | Impact |
|------|--------------|--------|
| Daily VRF (`_requestRng`) | `VRF_REQUEST_CONFIRMATIONS = 10` | Higher security for high-value daily draws |
| Mid-day VRF (`requestLootboxRng`) | `VRF_MIDDAY_CONFIRMATIONS = 3` | Lower latency for ticket trait assignment |

The 3-confirmation mid-day path is lower security than the 10-confirmation daily path. This is an intentional design tradeoff: ticket trait assignment has lower value-at-risk than daily jackpot draws. However, the analysis should note this asymmetry.

### Double-Buffer as Commit-Reveal Substitute
The ticket double-buffer serves as a structural commit-reveal mechanism: tickets are committed to the write buffer before any VRF word that will determine their traits. The `_swapTicketSlot` call atomically converts write->read, and `processTicketBatch` only operates on the read buffer. This means even if `lastLootboxRngWord` is publicly observable, an attacker cannot add or remove tickets from the read buffer to influence trait distribution.

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Manual audit analysis (no automated tests) |
| Config file | N/A |
| Quick run command | N/A (document review) |
| Full suite command | N/A (document review) |

### Phase Requirements -> Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| TICKET-01 | Full ticket creation trace with entropy sources | manual-only | Review audit/v1.2-ticket-rng-deep-dive.md Section 1 | Wave 0 |
| TICKET-02 | Mid-day RNG flow manipulation resistance | manual-only | Review audit/v1.2-ticket-rng-deep-dive.md Section 2 | Wave 0 |
| TICKET-03 | lastLootboxRngWord observability analysis | manual-only | Review audit/v1.2-ticket-rng-deep-dive.md Section 3 | Wave 0 |
| TICKET-04 | Coinflip lock timing gap analysis | manual-only | Review audit/v1.2-ticket-rng-deep-dive.md Section 4 | Wave 0 |

**Justification for manual-only:** This phase produces adversarial analysis documentation, not executable code. Verification is by document review against the success criteria (each section must contain the specified trace, reasoning, and verdict).

### Sampling Rate
- **Per task commit:** Verify section completeness against TICKET requirement
- **Per wave merge:** Cross-check traces against Phase 12 data flow document for consistency
- **Phase gate:** All 4 TICKET requirements have explicit verdicts; no EXPLOITABLE finding without escalation

### Wave 0 Gaps
None -- no test infrastructure needed for audit document production.

## Open Questions

1. **LCG Period and Trait Bias**
   - What we know: `_raritySymbolBatch` uses an LCG with `TICKET_LCG_MULT` constant. The seed is `uint64(seed) | 1` (forced odd) for "full LCG period." `DegenerusTraitUtils.traitFromWord(s)` applies a weighted distribution.
   - What's unclear: Whether the LCG produces a uniform distribution across the 256 traits (or has statistical bias). This is a correctness question, not a manipulation question -- the entropy source is VRF-derived regardless.
   - Recommendation: Note in the audit but do not assess as security-relevant. Trait distribution fairness is a game design issue, not an RNG manipulation vulnerability.

2. **Coinflip Deposit Lock at Non-x10 Levels**
   - What we know: `_coinflipLockedDuringTransition` only fires on x10 levels (BAF-eligible). At non-x10 levels, coinflip deposits are allowed even on lastPurchaseDay with rngLocked=true.
   - What's unclear: Whether coinflip deposits on non-x10 levels during rngLocked periods can influence any RNG outcome. Deposits trigger auto-claim (`_claimCoinflipsInternal`), which reads `coinflipDayResult[epoch]` (already determined). The deposit itself writes to player state for FUTURE epochs.
   - Recommendation: Trace the auto-claim path during deposits to confirm it only reads already-determined results and does not interact with pending VRF state. This should resolve as SAFE since auto-claim uses stored results, not pending words.

3. **VRF_MIDDAY_CONFIRMATIONS = 3 Security Implications**
   - What we know: Mid-day VRF uses 3 confirmations vs 10 for daily. Lower confirmations mean the VRF word arrives faster but has slightly lower finality guarantees.
   - What's unclear: Whether 3 confirmations is sufficient to prevent a validator from influencing the VRF word itself (not a protocol-level concern since VRF proof is verified on-chain, but relevant to the block reorg model).
   - Recommendation: Note the asymmetry in the audit. Since Chainlink VRF v2.5 verifies the proof on-chain regardless of confirmation count, the VRF word itself is cryptographically secure. The lower confirmation count only affects latency, not word integrity.

## Sources

### Primary (HIGH confidence)
- `contracts/storage/DegenerusGameStorage.sol` -- _queueTickets, _queueTicketsScaled, _swapTicketSlot, _tqWriteKey/_tqReadKey (direct source reading)
- `contracts/modules/DegenerusGameJackpotModule.sol` -- processTicketBatch, _processOneTicketEntry, _raritySymbolBatch, _rollRemainder (direct source reading)
- `contracts/modules/DegenerusGameAdvanceModule.sol` -- requestLootboxRng, rawFulfillRandomWords, advanceGame mid-day drain, _finalizeLootboxRng (direct source reading)
- `contracts/BurnieCoinflip.sol` -- _coinflipLockedDuringTransition, _depositCoinflip, claim functions with rngLocked guards (direct source reading)
- `audit/v1.2-rng-data-flow.md` -- Phase 12 data flow diagrams including mid-day ticket flow (Section 3)
- `audit/v1.2-manipulation-windows.md` -- Phase 14 L4 window analysis, inter-block jackpot gap analysis, consolidated verdicts

### Secondary (MEDIUM confidence)
- Chainlink VRF v2.5 confirmation model -- VRF proof verified on-chain regardless of confirmation count (established knowledge, stable)

## Metadata

**Confidence breakdown:**
- Ticket creation trace: HIGH - all code paths read directly from contract source, cross-referenced with Phase 12 data flow
- Mid-day RNG flow: HIGH - AdvanceModule:673-735 and :155-196 traced with buffer swap mechanics confirmed
- lastLootboxRngWord observability: HIGH - two write sites identified (AdvanceModule:166 and :789), storage visibility confirmed
- Coinflip lock timing: HIGH - _coinflipLockedDuringTransition conditions enumerated from source; separate claim guards identified
- LCG trait fairness: LOW - statistical properties of LCG not verified (out of scope for security audit)

**Research date:** 2026-03-14
**Valid until:** Indefinite (contract code is fixed, not a moving target)
