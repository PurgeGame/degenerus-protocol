# Stack Research: Bonus Jackpot Trait Split

**Domain:** Independent trait rolls for bonus (BURNIE/ticket) jackpot split
**Researched:** 2026-04-11
**Overall confidence:** HIGH

## 1. Entropy Derivation Strategy

### Current Entropy Architecture

The system derives all sub-entropy from a single VRF word (`randWord`) using two patterns:

**Pattern A -- XOR domain tagging (for entropy streams):**
```solidity
uint256 entropy = randWord ^ (uint256(lvl) << 192);                     // ETH jackpot
uint256 coinEntropy = randWord ^ (uint256(lvl) << 192) ^ uint256(COIN_JACKPOT_TAG);  // coin jackpot
uint256 entropy = rngWord ^ (uint256(lvl) << 192) ^ uint256(FAR_FUTURE_COIN_TAG);   // far-future coin
```

**Pattern B -- keccak256 domain separation (for single derived values):**
```solidity
keccak256(abi.encodePacked(randWord, DAILY_CARRYOVER_SOURCE_TAG, counter))  // source level
keccak256(abi.encodePacked(randWord, DAILY_CURRENT_BPS_TAG, counter))       // daily BPS
```

**Trait derivation (current single roll):**
```solidity
function _rollWinningTraits(uint256 randWord) private view returns (uint32) {
    uint8[4] memory traits = JackpotBucketLib.getRandomTraits(randWord);  // uses bits [0:23]
    _applyHeroOverride(traits, randWord);  // uses bits [0:11] for hero color
    return JackpotBucketLib.packWinningTraits(traits);
}
```

`getRandomTraits` consumes only 24 bits (bits 0-23, 6 per quadrant). `_applyHeroOverride` consumes up to 12 bits (bits 0-11, 3 per quadrant for color). The remaining 232 bits of the VRF word are untouched by trait derivation.

### Recommended Bonus Entropy Derivation

Use Pattern B (keccak256) to derive a fully independent seed for the bonus trait roll. This is the strongest independence guarantee.

```solidity
bytes32 private constant BONUS_TRAITS_TAG = keccak256("bonus-traits");

function _rollBonusTraits(uint256 randWord) private view returns (uint32) {
    uint256 bonusSeed = uint256(keccak256(abi.encodePacked(randWord, BONUS_TRAITS_TAG)));
    uint8[4] memory traits = JackpotBucketLib.getRandomTraits(bonusSeed);
    _applyHeroOverride(traits, bonusSeed);
    return JackpotBucketLib.packWinningTraits(traits);
}
```

**Why keccak256 over XOR:**
- XOR tagging preserves bit-level correlation (bit N of main = bit N of bonus XOR constant). For trait derivation that uses specific low bits, this means a static relationship between main and bonus trait values at the bit level. keccak256 completely destroys this relationship.
- The existing XOR pattern works for entropy *streams* (where downstream `entropyStep` calls diverge anyway), but for a one-shot trait roll consuming the same bit positions, keccak256 is necessary for true independence.
- keccak256 costs ~30 gas + 6 gas/word of input. With a 32-byte word + 32-byte tag = 64 bytes input, the cost is ~42 gas. Negligible.

**Independence proof:**
- Main traits: `getRandomTraits(randWord)` reads bits [0:23] of `randWord`
- Bonus traits: `getRandomTraits(keccak256(randWord || BONUS_TRAITS_TAG))` reads bits [0:23] of a cryptographic hash output
- These are statistically independent by the preimage resistance property of keccak256
- No bit-level correlation exists between the two sets of traits

**Hero override preservation:**
The hero override reads `_topHeroSymbol(day)` which is deterministic per day (it reads on-chain hero wager state). Both main and bonus rolls should apply the same hero override -- the override replaces a quadrant's trait with the hero symbol + a random color. The random color for the bonus roll uses the bonusSeed bits, producing an independently random color while preserving the same hero symbol.

### Alternative Considered: EntropyLib.entropyStep

```solidity
uint256 bonusSeed = EntropyLib.entropyStep(randWord);
```

Rejected because `entropyStep` is an XOR-shift PRNG, not a cryptographic hash. While sufficient for downstream winner selection (where it compounds across many steps), a single step from the same seed used for main traits creates a mathematically predictable relationship between main and bonus trait bits. The keccak256 approach is both cheaper in analysis effort and stronger in guarantee.

### Confidence: HIGH
Direct code inspection of all entropy patterns in JackpotModule. keccak256 domain separation is the established pattern in this codebase for independent value derivation (see `DAILY_CURRENT_BPS_TAG`, `DAILY_CARRYOVER_SOURCE_TAG`).

---

## 2. Event Design for Bonus Winning Traits

### Current Event Landscape

The module emits trait-indexed events per individual winner:
```solidity
event JackpotEthWin(address winner, uint24 level, uint8 traitId, uint256 amount, uint256 ticketIndex, uint24 rebuyLevel, uint32 rebuyTickets);
event JackpotTicketWin(address winner, uint24 ticketLevel, uint8 traitId, uint32 ticketCount, uint24 sourceLevel, uint256 ticketIndex);
event JackpotBurnieWin(address winner, uint24 level, uint8 traitId, uint256 amount, uint256 ticketIndex);
```

There is **no** event that emits the full set of 4 winning traits as a unit. The per-winner events carry the individual `traitId` that matched for each winner, but the 4 winning traits themselves exist only in:
1. Storage: `dailyJackpotTraitsPacked` (only for quest sync, overwritten each day)
2. Per-winner events: implicitly, by observing all 4 unique `traitId` values across emitted events

### Recommended: Dedicated Bonus Traits Event

```solidity
/// @dev Emitted once per bonus jackpot drawing to record the independent bonus winning traits.
///      No storage write -- event log only.
event BonusJackpotTraits(
    uint24 indexed level,
    uint32 bonusTraitsPacked   // 4x8-bit trait IDs, same packing as packWinningTraits
);
```

**Design rationale:**
- **One event per drawing**, not per winner. The bonus traits apply to all bonus winners; emitting once is sufficient and gas-cheap (375 base + 375 per indexed topic + 8 per byte of data = ~800 gas total).
- **Packed uint32 format** matches the existing `packWinningTraits` / `unpackWinningTraits` convention. Off-chain indexers can unpack identically to on-chain code.
- **Level indexed** enables efficient log filtering by level.
- **No storage** as specified in milestone requirements. The event log is the permanent record.

**Alternative considered: Emit 4 separate uint8 trait IDs.**
Rejected. Packing is the established convention (`_syncDailyWinningTraits` stores packed, `_loadDailyWinningTraits` reads packed). A packed uint32 is consistent, cheaper (32 bits vs 4x8 bits in log data), and trivially unpacked.

**Alternative considered: Extend existing per-winner events with a bonus flag.**
Rejected. The bonus traits are a property of the drawing, not of individual winners. Duplicating the trait set across N winner events wastes gas and is semantically wrong.

**Where to emit:** Inside `payDailyJackpotCoinAndTickets` (or its bonus-specific refactor), immediately after the bonus trait roll, before distributing to winners.

### Confidence: HIGH
Direct inspection of all 6 existing event signatures and emission sites.

---

## 3. Gas Impact of Rolling Traits Twice

### Cost Breakdown Per Trait Roll

| Operation | Gas | Notes |
|-----------|-----|-------|
| `keccak256(abi.encodePacked(randWord, BONUS_TRAITS_TAG))` | ~42 | 30 base + 6/word x 2 words |
| `getRandomTraits(bonusSeed)` | ~80 | 4 bitwise AND + 4 shifts + 4 additions; pure memory ops |
| `_applyHeroOverride(traits, bonusSeed)` | ~2,200 (cold) / ~200 (warm) | Reads `dailyHeroWagers` mapping (SLOAD), iterates 4x8 hero symbols |
| `packWinningTraits(traits)` | ~30 | 4 shifts + 3 ORs |
| `BonusJackpotTraits` event emission | ~800 | LOG2: 375 base + 375 topic + ~50 data |

**Total additional gas for bonus trait roll: ~3,150 (cold) / ~1,150 (warm)**

The cold path (first `_applyHeroOverride` call of the transaction) is the relevant case for `payDailyJackpot` Phase 1, where the main roll already warms the hero wager slot. So the bonus roll in the same transaction uses the warm path.

**Net gas cost of adding a second trait roll: ~1,150 gas.**

This is negligible relative to the total `payDailyJackpot` gas budget. For reference, a single `_randTraitTicket` winner selection costs ~5,000-8,000 gas (SLOAD + array access + keccak256), and daily ETH distribution processes 50-305 winners.

### Impact on Two-Call Split Threshold

The two-call split fires when total scaled winners exceed `JACKPOT_MAX_WINNERS` (160). The second trait roll does not add winners -- it only changes which traits are used for bonus distribution (BURNIE, carryover tickets). The split threshold is unaffected.

### Where the Second Roll Fits in the Call Flow

Current flow:
1. `payDailyJackpot` Phase 1: `_rollWinningTraits(randWord)` -> ETH distribution
2. `payDailyJackpotCoinAndTickets` Phase 2: Uses stored `winningTraitsPacked` for BURNIE + ticket distribution

Proposed flow:
1. `payDailyJackpot` Phase 1: `_rollWinningTraits(randWord)` -> ETH distribution (unchanged)
2. `payDailyJackpotCoinAndTickets` Phase 2: `_rollBonusTraits(randWord)` -> BURNIE + carryover ticket distribution

The bonus roll happens in Phase 2 where `randWord` is already available (passed as parameter). No additional SLOAD for the VRF word.

### Confidence: HIGH
Gas costs verified against Solidity opcode pricing (EIP-2929 warm/cold). Hero wager warming verified by tracing execution order in `payDailyJackpot`.

---

## 4. Packed Daily Jackpot Tracker (`dailyJackpotTraitsPacked`) Implications

### Current Layout

```
dailyJackpotTraitsPacked (uint256):
  [bits  0:31]  lastDailyJackpotWinningTraits  uint32   Packed 4x8-bit trait IDs (main)
  [bits 32:55]  lastDailyJackpotLevel          uint24   Level for the winning traits
  [bits 56:87]  lastDailyJackpotDay            uint32   Day index for winning traits
  [bits 88:255] UNUSED                                  168 bits free
```

### Does the Bonus Trait Roll Need Storage?

**No, it does not need persistent storage.** The reasons:

1. **The packed tracker's purpose is quest sync** (`_syncDailyWinningTraits` / `_loadDailyWinningTraits`). Quests only use the main winning traits to determine quest progress. Bonus traits are purely a distribution mechanism.

2. **The tracker bridges Phase 1 and Phase 2** of the two-call split. Phase 1 stores main traits; Phase 2 reads them back. But bonus traits are rolled fresh in Phase 2 from `randWord` (which is also available in Phase 2), so no cross-phase storage is needed.

3. **The milestone explicitly states "no storage"** for bonus winning traits -- event emission only.

### Could Bonus Traits Be Packed Here Anyway?

Yes, there is capacity: 168 free bits, and bonus traits are 32 bits. A `DJT_BONUS_TRAITS_SHIFT = 88` / `DJT_BONUS_TRAITS_MASK = 0xFFFFFFFF` field would fit trivially. However, this would:
- Add an unnecessary SSTORE (5,000 gas cold / 2,900 warm) for data that is never read back
- Violate the "no storage" requirement
- Create dead state that could confuse future auditors

**Recommendation: Do not modify `dailyJackpotTraitsPacked`.** The existing layout is untouched.

### What About `payDailyCoinJackpot` (Purchase Phase Coin Path)?

`payDailyCoinJackpot` (line 1661) currently reads from `dailyJackpotTraitsPacked` via `_loadDailyWinningTraits` to reuse the main traits. Under the bonus split, this function should also roll independent bonus traits for its BURNIE distribution. Since it already has `randWord` as a parameter, the same `keccak256(randWord, BONUS_TRAITS_TAG)` derivation works here too, with no tracker dependency.

### Confidence: HIGH
Direct inspection of all `_djtRead` / `_djtWrite` callsites (6 total), packed layout documentation, and the two-call split flow.

---

## 5. Summary: Required Stack Additions

### New Constants

| Constant | Value | Purpose |
|----------|-------|---------|
| `BONUS_TRAITS_TAG` | `keccak256("bonus-traits")` | Domain separator for bonus trait entropy derivation |

### New Functions

| Function | Signature | Purpose |
|----------|-----------|---------|
| `_rollBonusTraits` | `(uint256 randWord) -> uint32` | keccak256-derived independent trait roll with hero override |

### New Events

| Event | Signature | Purpose |
|-------|-----------|---------|
| `BonusJackpotTraits` | `(uint24 indexed level, uint32 bonusTraitsPacked)` | Record bonus winning traits (no storage) |

### Modified Functions

| Function | Change | Impact |
|----------|--------|--------|
| `payDailyJackpotCoinAndTickets` | Roll bonus traits; use for BURNIE + carryover ticket distribution | ~1,150 gas increase |
| `payDailyCoinJackpot` | Roll bonus traits instead of reading main traits from storage | ~1,150 gas increase, removes SLOAD dependency on tracker |

### Unchanged

| Component | Why Unchanged |
|-----------|---------------|
| `dailyJackpotTraitsPacked` | Bonus traits need no persistent storage; quest sync uses main traits only |
| `_rollWinningTraits` | Main trait roll is unmodified; continues to serve ETH distribution |
| `getRandomTraits` | Library function unchanged; called with different seed for bonus |
| `_applyHeroOverride` | Called for both main and bonus; hero symbol deterministic per day |
| ETH distribution flow | Main traits still govern ETH bucket assignment |
| Two-call split logic | No additional winners from bonus roll; threshold unaffected |
| `EntropyLib` | No changes needed; entropyStep still used downstream for winner selection |

### Coin Target Level Change

The milestone specifies narrowing the bonus coin target range from `[lvl, lvl+4]` to `[lvl+1, lvl+4]`. This is a one-line change:

```solidity
// Current: _selectDailyCoinTargetLevel returns lvl + entropy % 5
// Proposed for bonus: lvl + 1 + (entropy % 4)
```

This affects `_selectDailyCoinTargetLevel` or a new bonus-specific variant. The change excludes current-level tickets from BURNIE distribution (since current-level is the main jackpot's domain). Gas impact: zero (same modulo operation, different constant).

---

## Alternatives Considered

| Category | Recommended | Alternative | Why Not |
|----------|-------------|-------------|---------|
| Entropy derivation | `keccak256(randWord, BONUS_TRAITS_TAG)` | XOR with tag (`randWord ^ BONUS_TRAITS_TAG`) | XOR preserves bit-level correlation at positions used by `getRandomTraits`; keccak256 guarantees cryptographic independence |
| Entropy derivation | `keccak256(randWord, BONUS_TRAITS_TAG)` | `EntropyLib.entropyStep(randWord)` | Single XOR-shift step has predictable bit-relationship to input; insufficient for same-position bit consumption |
| Event format | Packed `uint32` | 4 separate `uint8` args | Inconsistent with `packWinningTraits` convention; more log data bytes |
| Event frequency | Once per drawing | Once per winner | Bonus traits are drawing-level, not winner-level; per-winner wastes gas |
| Storage | No storage for bonus traits | Pack into `dailyJackpotTraitsPacked` bits [88:119] | Unnecessary SSTORE; violates "no storage" requirement; dead state |

## Sources

- `contracts/modules/DegenerusGameJackpotModule.sol` -- all trait derivation, entropy patterns, event signatures, distribution flows (HIGH confidence, direct code inspection)
- `contracts/libraries/JackpotBucketLib.sol` -- `getRandomTraits` bit consumption (bits [0:23]), `packWinningTraits`/`unpackWinningTraits` format (HIGH confidence, direct code inspection)
- `contracts/libraries/EntropyLib.sol` -- `entropyStep` XOR-shift algorithm (HIGH confidence, direct code inspection)
- `contracts/storage/DegenerusGameStorage.sol` lines 924-952 -- `dailyJackpotTraitsPacked` layout, 88/256 bits used, 168 free (HIGH confidence, direct code inspection)
- EVM opcode pricing: LOG2 = 375 + 375/topic + 8/byte (EIP-2929, HIGH confidence)
- keccak256 gas: 30 base + 6/word (Yellow Paper, HIGH confidence)
- SLOAD pricing: 2,100 cold / 100 warm (EIP-2929, HIGH confidence)

---
*Stack research for: Independent bonus trait roll in DegenerusGameJackpotModule*
*Researched: 2026-04-11*
