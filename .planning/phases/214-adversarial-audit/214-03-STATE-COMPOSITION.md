# Adversarial Audit: State Corruption + Composition Attack Pass

**Scope:** All changed/new functions in v5.0-to-HEAD delta (per 213-DELTA-EXTRACTION.md Phase 214 scope)
**Method:** Fresh audit (per D-02) -- no prior audit artifacts referenced
**Chains in scope:** SM-01 through SM-56, EF-01 through EF-20, RNG-01 through RNG-11, RO-01 through RO-12 (per D-03)

## Methodology

### State Corruption
For each function:
1. Identify all storage writes (SSTORE sites, packed field writes via helpers)
2. For packed bitfield operations: verify read-modify-write atomicity (no concurrent mutation from re-entry or parallel paths)
3. For memory-then-store patterns: verify ALL memory computations are flushed to storage before any external call or return
4. For struct repacking: verify no field overlap, no uninitialized bits interpreted as data
5. For moved functions: verify the function writes to exactly the same storage slots in the new location

### Composition Attacks
For each function pair/chain:
1. Can function A leave state that function B misinterprets?
2. Can calling A then B produce a state that neither A nor B can produce alone?
3. For the 99 cross-module chains: does the chain's state mutation sequence remain consistent across all possible ordering?
4. For the EndgameModule redistribution: does calling the redistributed function produce identical state effects?

## Findings

No VULNERABLE findings. All functions analyzed produce SAFE or INFO verdicts for both state corruption and composition attack vectors.

## Packed State Field Audit

### Slot 0 Repack

Slot 0 packs 30 bytes of timing, FSM, counters, flags, and buffer state. 2 bytes unused padding at the end.

| Field | Bits | Bytes | Shift | Mask | Read | Write | Verdict |
|-------|------|-------|-------|------|------|-------|---------|
| purchaseStartDay | 32 | [0:4] | 0 | 0xFFFFFFFF | direct | direct | SAFE |
| dailyIdx | 32 | [4:8] | 32 | 0xFFFFFFFF | direct | direct | SAFE |
| rngRequestTime | 48 | [8:14] | 64 | 0xFFFFFFFFFFFF | direct | direct | SAFE |
| level | 24 | [14:17] | 112 | 0xFFFFFF | direct (public) | direct | SAFE |
| jackpotPhaseFlag | 8 | [17:18] | 136 | 0x1 | direct | direct | SAFE |
| jackpotCounter | 8 | [18:19] | 144 | 0xFF | direct | direct | SAFE |
| lastPurchaseDay | 8 | [19:20] | 152 | 0x1 | direct | direct | SAFE |
| decWindowOpen | 8 | [20:21] | 160 | 0x1 | direct | direct | SAFE |
| rngLockedFlag | 8 | [21:22] | 168 | 0x1 | direct | direct | SAFE |
| phaseTransitionActive | 8 | [22:23] | 176 | 0x1 | direct | direct | SAFE |
| gameOver | 8 | [23:24] | 184 | 0x1 | direct (public) | direct | SAFE |
| dailyJackpotCoinTicketsPending | 8 | [24:25] | 192 | 0x1 | direct | direct | SAFE |
| compressedJackpotFlag | 8 | [25:26] | 200 | 0xFF | direct | direct | SAFE |
| ticketsFullyProcessed | 8 | [26:27] | 208 | 0x1 | direct | direct | SAFE |
| gameOverPossible | 8 | [27:28] | 216 | 0x1 | direct | direct | SAFE |
| ticketWriteSlot | 8 | [28:29] | 224 | 0x1 | direct | direct | SAFE |
| prizePoolFrozen | 8 | [29:30] | 232 | 0x1 | direct | direct | SAFE |
| (padding) | 16 | [30:32] | - | - | - | - | SAFE |

**Analysis:** Slot 0 uses Solidity's native sequential packing. Each variable is its own named storage variable with its own type. There are NO manual bit-shift operations on slot 0 -- the EVM handles field isolation automatically via Solidity's compiler. All reads and writes use the variable name directly. No overlap risk. The 2-byte padding is compiler-managed and never accessed. Total: 30 bytes used, 2 padding.

**Atomicity:** Because each field is a separate Solidity variable packed by the compiler into one slot, a single write (e.g., `rngLockedFlag = true`) performs a read-modify-write at the EVM level on the entire 32-byte slot. Since Ethereum execution is single-threaded within a transaction, there is no concurrent mutation risk. Re-entrancy is the only concern, and all re-entrant paths are gated by `rngLockedFlag` mutual exclusion.

**Verdict: SAFE** -- compiler-managed packing, no manual bit manipulation, no field overlap.

### Slot 1 Repack (currentPrizePool uint128 + claimablePool uint128)

| Field | Bits | Shift | Access Helper | Verdict |
|-------|------|-------|---------------|---------|
| currentPrizePool | 128 | [0:128] | _getCurrentPrizePool / _setCurrentPrizePool | SAFE |
| claimablePool | 128 | [128:256] | direct read / `+= uint128(delta)` | SAFE |

**Analysis:** Both are Solidity-typed `uint128` variables declared sequentially. The compiler packs them into one 32-byte slot. `currentPrizePool` occupies the low 128 bits, `claimablePool` the high 128 bits. Access:

1. `_getCurrentPrizePool()` returns `uint256(currentPrizePool)` -- reads the low 128 bits.
2. `_setCurrentPrizePool(val)` assigns `currentPrizePool = uint128(val)` -- writes the low 128 bits.
3. `claimablePool` is accessed directly via `claimablePool += uint128(delta)`.

Both writes use Solidity's native variable access, so the compiler's read-modify-write on the shared slot is atomic within a transaction. A write to `currentPrizePool` does NOT corrupt `claimablePool` because the compiler emits the correct field-isolated SSTORE.

**Concern checked:** In `_consolidatePoolsAndRewardJackpots`, `currentPrizePool = uint128(memCurrent)` and `claimablePool += uint128(claimableDelta)` are separate Solidity statements. Each statement reads the full slot, modifies only its field, and writes back. Because these are sequential (no external call between them), the second write sees the first write's result. If there were an external call between them, re-entrancy could be a concern, but the function has no external call between these two writes (the self-calls to `runBafJackpot` and `runDecimatorJackpot` occur BEFORE the SSTORE batch at line 790-794).

**Verdict: SAFE** -- compiler-managed packing, sequential writes with no interleaving external calls.

### presaleStatePacked

Layout (LSB to MSB):
| Field | Bits | Shift | Mask | Read Helper | Write Helper | Verdict |
|-------|------|-------|------|-------------|--------------|---------|
| lootboxPresaleActive | 8 | PS_ACTIVE_SHIFT=0 | PS_ACTIVE_MASK=0xFF | _psRead(0, 0xFF) | _psWrite(0, 0xFF, val) | SAFE |
| lootboxPresaleMintEth | 128 | PS_MINT_ETH_SHIFT=8 | PS_MINT_ETH_MASK=0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF | _psRead(8, ...) | _psWrite(8, ..., val) | SAFE |
| (unused) | 120 | [136:256] | - | - | - | SAFE |

**Analysis:** Total bits used = 8 + 128 = 136 of 256. No overlap between the two fields (bits 0-7 vs bits 8-135). The `_psRead` and `_psWrite` helpers use the standard pattern: `(packed >> shift) & mask` for reads, `(packed & ~(mask << shift)) | ((value & mask) << shift)` for writes. Mask values are correct: `0xFF` is 8 bits, `0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF` is 128 bits (32 hex chars = 128 bits).

**Consumers:** MintModule.purchase (presale mint ETH accumulation), AdvanceModule.advanceGame (presale auto-end check), WhaleModule._purchaseWhaleBundle (presale check).

**Verdict: SAFE** -- no overlap, correct shift/mask, standard read-modify-write pattern.

### gameOverStatePacked

Layout (LSB to MSB):
| Field | Bits | Shift | Mask | Read Helper | Write Helper | Verdict |
|-------|------|-------|------|-------------|--------------|---------|
| gameOverTime | 48 | GO_TIME_SHIFT=0 | GO_TIME_MASK=0xFFFFFFFFFFFF | _goRead(0, ...) | _goWrite(0, ..., val) | SAFE |
| gameOverFinalJackpotPaid | 8 | GO_JACKPOT_PAID_SHIFT=48 | GO_JACKPOT_PAID_MASK=0xFF | _goRead(48, 0xFF) | _goWrite(48, 0xFF, val) | SAFE |
| finalSwept | 8 | GO_SWEPT_SHIFT=56 | GO_SWEPT_MASK=0xFF | _goRead(56, 0xFF) | _goWrite(56, 0xFF, val) | SAFE |
| (unused) | 192 | [64:256] | - | - | - | SAFE |

**Analysis:** Total bits used = 48 + 8 + 8 = 64. No overlap. Shift positions are non-overlapping: [0:47], [48:55], [56:63]. Masks match widths. `_goRead` and `_goWrite` use the standard pattern.

**Consumers:** GameOverModule.handleGameOverDrain (writes gameOverTime, gameOverFinalJackpotPaid), GameOverModule.handleFinalSweep (reads gameOverTime, writes finalSwept), DegenerusGame._claimWinningsInternal (reads finalSwept for sweep guard).

**Atomicity concern:** `handleGameOverDrain` writes two fields (`GO_TIME` then `GO_JACKPOT_PAID`) in separate `_goWrite` calls. Each call is a full read-modify-write on the same slot. No external call between them (gameOver latch and burnAtGameOver calls are BETWEEN the time write at line 137 and the jackpot paid write at line 143, but `charityGameOver.burnAtGameOver()` at line 140 is an external call. However, the GNRUS `burnAtGameOver` does NOT read `gameOverStatePacked` -- it only reads its own `finalized` flag and modifies its own GNRUS balances. Re-entrancy back into Game is blocked because `gameOver = true` is already set at line 136, and `_handleGameOverPath` checks `gameOver` on re-entry.

**Verdict: SAFE** -- no overlap, correct masks, re-entrancy blocked by gameOver flag.

### dailyJackpotTraitsPacked

Layout (LSB to MSB):
| Field | Bits | Shift | Mask | Read Helper | Write Helper | Verdict |
|-------|------|-------|------|-------------|--------------|---------|
| lastDailyJackpotWinningTraits | 32 | DJT_TRAITS_SHIFT=0 | DJT_TRAITS_MASK=0xFFFFFFFF | _djtRead(0, ...) | _djtWrite(0, ..., val) | SAFE |
| lastDailyJackpotLevel | 24 | DJT_LEVEL_SHIFT=32 | DJT_LEVEL_MASK=0xFFFFFF | _djtRead(32, ...) | _djtWrite(32, ..., val) | SAFE |
| lastDailyJackpotDay | 32 | DJT_DAY_SHIFT=56 | DJT_DAY_MASK=0xFFFFFFFF | _djtRead(56, ...) | _djtWrite(56, ..., val) | SAFE |
| (unused) | 168 | [88:256] | - | - | - | SAFE |

**Analysis:** Total bits = 32 + 24 + 32 = 88. Field boundaries: [0:31], [32:55], [56:87]. No overlap. Masks are correct (32-bit, 24-bit, 32-bit).

**Consumers:** JackpotModule._syncDailyWinningTraits (writes all three), JackpotModule._loadDailyWinningTraits (reads all three), JackpotModule.payDailyJackpotCoinAndTickets (reads traits and level).

**Verdict: SAFE** -- no overlap, correct shifts and masks.

### mintPacked_ (per-player)

Full 256-bit layout:
| Field | Bits | Shift Constant | Mask | Verdict |
|-------|------|----------------|------|---------|
| LAST_LEVEL | [0:23] | LAST_LEVEL_SHIFT=0 | MASK_24 | SAFE |
| LEVEL_COUNT | [24:47] | LEVEL_COUNT_SHIFT=24 | MASK_24 | SAFE |
| LEVEL_STREAK | [48:71] | LEVEL_STREAK_SHIFT=48 | MASK_24 | SAFE |
| DAY | [72:103] | DAY_SHIFT=72 | MASK_32 | SAFE |
| LEVEL_UNITS_LEVEL | [104:127] | LEVEL_UNITS_LEVEL_SHIFT=104 | MASK_24 | SAFE |
| FROZEN_UNTIL_LEVEL | [128:151] | FROZEN_UNTIL_LEVEL_SHIFT=128 | MASK_24 | SAFE |
| WHALE_BUNDLE_TYPE | [152:153] | WHALE_BUNDLE_TYPE_SHIFT=152 | MASK_2 (0x3) | SAFE |
| (unused) | [154:159] | - | - | SAFE |
| MINT_STREAK_LAST_COMPLETED | [160:183] | 160 | MASK_24 | SAFE |
| HAS_DEITY_PASS | [184] | HAS_DEITY_PASS_SHIFT=184 | MASK_1 (0x1) | SAFE |
| AFFILIATE_BONUS_LEVEL | [185:208] | AFFILIATE_BONUS_LEVEL_SHIFT=185 | MASK_24 | SAFE |
| AFFILIATE_BONUS_POINTS | [209:214] | AFFILIATE_BONUS_POINTS_SHIFT=209 | MASK_6 (0x3F) | SAFE |
| (unused) | [215:227] | - | - | SAFE |
| LEVEL_UNITS | [228:243] | LEVEL_UNITS_SHIFT=228 | MASK_16 | SAFE |
| (reserved) | [244:255] | - | - | SAFE |

**Overlap analysis:**
- HAS_DEITY_PASS at bit 184 (1 bit) ends at 184. AFFILIATE_BONUS_LEVEL starts at bit 185. No overlap.
- AFFILIATE_BONUS_LEVEL at [185:208] (24 bits: 185 + 24 - 1 = 208). AFFILIATE_BONUS_POINTS starts at 209. No overlap.
- AFFILIATE_BONUS_POINTS at [209:214] (6 bits: 209 + 6 - 1 = 214). Unused gap at [215:227]. No overlap.
- WHALE_BUNDLE_TYPE at [152:153] (2 bits). Unused gap [154:159]. MINT_STREAK_LAST_COMPLETED at [160:183]. No overlap.
- LEVEL_UNITS at [228:243] (16 bits). Reserved [244:255]. No overlap with AFFILIATE_BONUS_POINTS ending at 214.

**All operations use `BitPackingLib.setPacked(data, shift, mask, value)`** which follows the standard `(data & ~(mask << shift)) | ((value & mask) << shift)` pattern. Reads use `(data >> shift) & mask`.

**Consumers verified:** AdvanceModule._enforceDailyMintGate (reads DAY, HAS_DEITY_PASS, FROZEN_UNTIL_LEVEL), MintModule.recordMintData (writes multiple fields), WhaleModule.purchaseDeityPass (writes HAS_DEITY_PASS), MintStreakUtils._playerActivityScore (reads LEVEL_STREAK, LEVEL_COUNT, AFFILIATE_BONUS), all callers use correct shift/mask pairs from BitPackingLib constants.

**Verdict: SAFE** -- no field overlaps, all bit boundaries verified, standard read-modify-write via BitPackingLib.

### Lootbox RNG Packed (_lrRead/_lrWrite)

Layout (LSB to MSB):
| Field | Bits | Shift | Mask | Description | Verdict |
|-------|------|-------|------|-------------|---------|
| lootboxRngIndex | [0:47] | LR_INDEX_SHIFT=0 | 0xFFFFFFFFFFFF (48 bits) | Index counter | SAFE |
| lootboxRngPendingEth | [48:111] | LR_PENDING_ETH_SHIFT=48 | 0xFFFFFFFFFFFFFFFF (64 bits) | milli-ETH encoded | SAFE |
| lootboxRngThreshold | [112:175] | LR_THRESHOLD_SHIFT=112 | 0xFFFFFFFFFFFFFFFF (64 bits) | milli-ETH encoded | SAFE |
| lootboxRngMinLinkBalance | [176:183] | LR_MIN_LINK_SHIFT=176 | 0xFF (8 bits) | whole LINK | SAFE |
| lootboxRngPendingBurnie | [184:223] | LR_PENDING_BURNIE_SHIFT=184 | 0xFFFFFFFFFF (40 bits) | whole BURNIE | SAFE |
| midDayTicketRngPending | [224:231] | LR_MID_DAY_SHIFT=224 | 0xFF (8 bits) | bool flag | SAFE |
| (unused) | [232:255] | - | - | 24 bits | SAFE |

**Overlap analysis:** Field boundaries: [0:47], [48:111], [112:175], [176:183], [184:223], [224:231]. Total = 48+64+64+8+40+8 = 232 bits used. No overlap.

**Encoding roundtrip verification:**
- ETH packing: `_packEthToMilliEth(wei_)` = `uint64(wei_ / 1e15)`, unpack: `uint256(milli) * 1e15`. Roundtrip: loses sub-milli-ETH precision (< 0.001 ETH). Acceptable for threshold and pending accumulation.
- BURNIE packing: `_packBurnieToWhole(wei_)` = `uint40(wei_ / 1e18)`, unpack: `uint256(whole) * 1e18`. Roundtrip: loses sub-token precision (< 1 BURNIE). Acceptable for threshold checks.
- The truncation is one-directional (pack loses precision, unpack restores to rounded value). No accumulation error because pending values are reset to 0 when a VRF request fires.

**Consumers:** AdvanceModule.requestLootboxRng (reads threshold, pending ETH/BURNIE, midDay; writes index, pending reset), AdvanceModule.advanceGame (reads midDay, index), DegeneretteModule._collectBetFunds (writes pending ETH/BURNIE), MintModule (writes pending ETH/BURNIE), WhaleModule (writes pending ETH).

**Verdict: SAFE** -- no overlap, encoding/decoding is consistent, precision loss is acceptable and bounded.

## EndgameModule Redistribution Verification

| Original Function (EndgameModule) | New Location | State Writes | State Equivalence | Verdict |
|-----------------------------------|-------------|--------------|-------------------|---------|
| rewardTopAffiliate | AdvanceModule._rewardTopAffiliate (private) | affiliate.affiliateTop read, dgnrs.transferFromPool (external), levelDgnrsAllocation[lvl] write | EQUIVALENT: Same external calls in same order. Event AffiliateDgnrsReward emitted with same parameters. levelDgnrsAllocation write identical. The only difference is that the old version was a delegatecall hop (Game -> AdvanceModule -> EndgameModule), now it is a direct private call within AdvanceModule. Since all modules execute in Game's storage context via delegatecall, the storage writes target the same slots. | SAFE |
| runRewardJackpots | AdvanceModule._consolidatePoolsAndRewardJackpots (inlined) | BAF: `IDegenerusGame(address(this)).runBafJackpot(bafPoolWei, lvl, rngWord)` (self-call). Decimator: `IDegenerusGame(address(this)).runDecimatorJackpot(decPoolWei, lvl, rngWord)` (self-call). memFuture/claimableDelta updated in memory. | EQUIVALENT: Both BAF and Decimator dispatch use the same self-call pattern. The old EndgameModule also dispatched via self-calls from delegatecall context. The pool arithmetic (baf percentage, decimator percentage) is identical. The key difference is that pool values are now in memory variables (memFuture) rather than reading/writing storage between calls. This is SAFER because intermediate storage writes between self-calls are eliminated. | SAFE |
| _addClaimableEth | JackpotModule._addClaimableEth (modified return) | claimableWinnings[beneficiary] write, autoRebuyState read, ticket queue writes (if auto-rebuy). Returns 3-tuple (claimableDelta, rebuyLevel, rebuyTickets). | EQUIVALENT: The storage writes are identical -- `_creditClaimable` writes to `claimableWinnings`, auto-rebuy writes to `_queueTickets` and pool variables. The return value change (void -> tuple) adds data for event emission but does not alter state writes. | SAFE |
| _runBafJackpot -> runBafJackpot | JackpotModule.runBafJackpot (external, self-call) | claimableWinnings writes via _addClaimableEth, whalePassClaims writes via _queueWhalePassClaimCore, ticket queue writes. Returns claimableDelta. | EQUIVALENT: The function body is identical. Making it `external` (instead of private in EndgameModule) means it is now called via `IDegenerusGame(address(this)).runBafJackpot()` which is a self-call that routes back through Game's fallback to JackpotModule via delegatecall. Storage context remains Game's. The `msg.sender != address(this)` guard ensures only self-calls succeed. State writes are identical. | SAFE |
| claimWhalePass | WhaleModule.claimWhalePass | whalePassClaims[player] clear, _applyWhalePassStats (mintPacked_ writes), _queueTicketRange (ticketQueue, ticketsOwedPacked writes). | EQUIVALENT: The function body is identical. `whalePassClaims[player] = 0` clear-before-use pattern preserved. `_queueTicketRange` call with same parameters. The only addition is `rngBypass: false` as the 5th parameter to `_queueTicketRange`, which was the default behavior -- whale pass claims during normal gameplay should respect rngLocked. Storage writes target same slots. | SAFE |

## Pool Consolidation Write-Batch Integrity

Detailed analysis of `_consolidatePoolsAndRewardJackpots` (AdvanceModule lines 620-797):

**1. Which pool values are loaded into memory at the start?**

```
uint256 memFuture = _getFuturePrizePool();    // reads prizePoolsPacked high 128 bits
uint256 memCurrent = _getCurrentPrizePool();  // reads currentPrizePool (slot 1 low 128)
uint256 memNext = _getNextPrizePool();        // reads prizePoolsPacked low 128 bits
uint256 memYieldAcc = yieldAccumulator;       // reads yieldAccumulator (own slot)
```

All four pool values are captured as local memory variables at function entry.

**2. Which computations modify the in-memory values?**

- Time-based future take: `memNext -= take + insuranceSkim; memFuture += take; memYieldAcc += insuranceSkim`
- x00 yield dump: `memFuture += half; memYieldAcc -= half`
- BAF jackpot: `memFuture -= claimed; claimableDelta += claimed`
- Decimator jackpot: `memFuture -= spend; claimableDelta += spend`
- x00 keep roll: `memFuture -= moveWei; memCurrent += moveWei`
- Merge next->current: `memCurrent += memNext; memNext = 0`
- Coinflip credit: external call to `coinflip.creditFlip` (no pool state change)
- Future->next drawdown: `memFuture -= reserved; memNext = reserved`

**3. At what point is the single SSTORE batch executed?**

Lines 790-794:
```
_setPrizePools(uint128(memNext), uint128(memFuture));  // writes prizePoolsPacked
currentPrizePool = uint128(memCurrent);                 // writes slot 1 low 128
yieldAccumulator = memYieldAcc;                         // writes own slot
if (claimableDelta != 0) {
    claimablePool += uint128(claimableDelta);            // writes slot 1 high 128
}
```

This is the ONLY point where pool storage is written.

**4. Is there ANY code path where an external call occurs between memory load and storage write?**

YES -- three external calls occur between memory load (lines 627-630) and storage write (lines 790-794):

1. `IDegenerusGame(address(this)).runBafJackpot(bafPoolWei, lvl, rngWord)` at line 719 -- self-call
2. `IDegenerusGame(address(this)).runDecimatorJackpot(decPoolWei, lvl, rngWord)` at line 731/742 -- self-call
3. `coinflip.creditFlip(ContractAddresses.SDGNRS, ...)` at line 776 -- external call

**5. Can the self-call to Game.runBafJackpot() cause a storage write that conflicts with the pending memory batch?**

The self-call routes to `JackpotModule.runBafJackpot()` via delegatecall. Inside `runBafJackpot`:
- It writes to `claimableWinnings[winner]` via `_addClaimableEth` -> `_creditClaimable` -- this is a DIFFERENT storage slot (mapping) from the pool slots held in memory.
- Auto-rebuy in `_addClaimableEth._processAutoRebuy` calls `_setFuturePrizePool` or `_setNextPrizePool` -- these WRITE to `prizePoolsPacked` storage, which is the SAME slot that `memFuture`/`memNext` will overwrite at the batch write point.

**CRITICAL CHECK:** If `_addClaimableEth` fires auto-rebuy inside `runBafJackpot`, it writes to `prizePoolsPacked`. Then when `_consolidatePoolsAndRewardJackpots` reaches line 790 (`_setPrizePools`), it overwrites `prizePoolsPacked` with the memory values (which do NOT include the auto-rebuy writes).

**RESOLUTION:** This is SAFE because `gameOver` is checked in `_addClaimableEth` at line 781-782: `if (!gameOver) { ... autoRebuyEnabled ... }`. During pool consolidation, `gameOver` is `false`. The auto-rebuy path in `_processAutoRebuy` at line 823-826 writes:
```
_setFuturePrizePool(_getFuturePrizePool() + calc.ethSpent);   // or _setNextPrizePool
```

This reads current storage (which is the PRE-consolidation value, NOT the in-progress memory value) and adds to it. Then the memory batch write at line 790 overwrites with `memFuture` (which was computed from the PRE-consolidation read). The auto-rebuy's storage write is OVERWRITTEN.

**HOWEVER:** The `claimableDelta` returned by `runBafJackpot` only accounts for ETH that went to `claimableWinnings` -- NOT the ETH that went to auto-rebuy pool deposits. The caller (`_consolidatePoolsAndRewardJackpots`) does `memFuture -= claimed` where `claimed = claimableDelta`. If auto-rebuy converted some ETH to tickets (pool deposits), that ETH is NOT in `claimableDelta` and thus NOT deducted from `memFuture`. The effect is: the auto-rebuy pool deposit is lost (overwritten by memory batch), but the tickets were queued. This means tickets are created but the pool backing is not incremented.

**WAIT -- RECHECK:** Looking at `runBafJackpot` more carefully. The returned `claimableDelta` is accumulated as:
```
(uint256 cd, uint24 rl, uint32 rt) = _addClaimableEth(winner, ethPortion, rngWord);
claimableDelta += cd;
```

In `_addClaimableEth`, when auto-rebuy fires, `_processAutoRebuy` returns `(calc.reserved, calc.targetLevel, calc.ticketCount)`. `calc.reserved` is the take-profit portion that goes to `claimableWinnings`. The rebuy portion (`calc.ethSpent`) goes to the pool via `_setFuturePrizePool`/`_setNextPrizePool`. So `claimableDelta` only includes the take-profit portion, NOT the full `ethPortion`.

The total ETH allocated to this winner from `memFuture` is `ethPortion`. Of that, `calc.reserved` goes to claimable (tracked in `claimableDelta`), and `calc.ethSpent` goes to pool (written to storage, then overwritten). The tickets are queued for `calc.ethSpent` worth of pool backing that will be overwritten.

**BUT:** Re-reading `_processAutoRebuy` in `JackpotModule` lines 798-834: The function writes `_queueTickets` for the tickets AND writes to `_setFuturePrizePool` or `_setNextPrizePool` for the pool backing. When the parent `_consolidatePoolsAndRewardJackpots` overwrites the pools with memory values, the auto-rebuy's pool increment is indeed lost. HOWEVER, the `memFuture -= claimed` line (line 724) deducts only `claimableDelta` (take-profit portion) from `memFuture`. The `ethSpent` portion (which went to the pool but will be overwritten) is still accounted for in `memFuture` -- it was NOT deducted! So `memFuture` is too large by exactly `ethSpent`.

Wait, let me re-read. The BAF pool is `bafPoolWei = (baseMemFuture * bafPct) / 100`. The self-call returns `claimed`. Then `memFuture -= claimed`. So `memFuture` drops by `claimed` (the claimable portion). The remaining `bafPoolWei - claimed` stays in `memFuture`. This remaining amount equals the sum of: (a) lootbox/ticket portions that stay in future pool implicitly, (b) auto-rebuy pool deposits that were written to storage but will be overwritten.

For (b), the auto-rebuy deposits `ethSpent` to `_setFuturePrizePool` or `_setNextPrizePool` in storage. But the memory batch at line 790 writes `memFuture` (which still contains the full `bafPoolWei - claimed` amount, INCLUDING the `ethSpent` portion that was "spent" on auto-rebuy). So the pools end up WITH the auto-rebuy backing because `memFuture` was never decremented by `ethSpent`. The storage write by auto-rebuy is redundant -- it writes the same direction (increment) to a variable that already has the value in memory. The memory batch overwrite is correct because the money never left `memFuture`.

**FINAL ANALYSIS:** The pattern is: BAF pool is allocated from `memFuture`. The self-call distributes it. Only the `claimableDelta` (ETH going to player claims) is deducted from `memFuture`. ETH going to auto-rebuy pool deposits, lootbox ticket queuing, or whale pass claims all implicitly STAY in the future pool because they are not deducted from `memFuture`. The auto-rebuy's storage write is overwritten, but since the corresponding amount was never deducted from `memFuture`, the pool remains correctly funded. The comment at line 2057-2058 confirms: "Refund + lootbox + whale pass ETH stays in futurePool implicitly: caller only deducts claimableDelta from memFuture."

**6. Verdict: SAFE** -- all pool math is memory-isolated. External calls (self-calls to BAF/Decimator and external call to coinflip.creditFlip) cannot corrupt the memory batch because: (a) only `claimableDelta` is deducted from memory pools, (b) non-claimable portions remain in memory pools implicitly, (c) the final SSTORE batch writes all four pool values atomically, and (d) any intermediate storage writes by auto-rebuy are harmlessly overwritten with correct values.

## Two-Call Split State Consistency

Analysis of the CALL1/CALL2 pattern in `_processDailyEth` (JackpotModule lines 1182-1292):

**1. What state is written after CALL1 to resumeEthPool?**

At line 1289-1291:
```
if (splitMode == SPLIT_CALL1) {
    resumeEthPool = uint128(ethPool);
}
```

`resumeEthPool` stores the ORIGINAL `ethPool` value passed to CALL1. Additionally, CALL1 writes:
- `claimablePool += uint128(liabilityDelta)` at line 1284-1286 for winners in the largest + solo buckets.
- `claimableWinnings[winner]` updates for each winner.
- Pool writes via auto-rebuy in `_addClaimableEth` (if auto-rebuy is enabled for winners).

Also, at `_resumeDailyEth` (the CALL2 entry point), the function reconstructs the full parameter set from stored state (daily jackpot traits, bucket counts, etc.) and calls `_processDailyEth` with `splitMode=SPLIT_CALL2`.

**2. What state does CALL2 (_resumeDailyEth) read to reconstruct?**

CALL2 reads:
- `resumeEthPool`: the stored ETH pool snapshot
- `_djtRead` packed field: winning traits from storage (written by `_syncDailyWinningTraits` before CALL1)
- Level, jackpotCounter: slot 0 variables
- RNG word: from `rngWordByDay[day]` (immutable once written)

It then calls `_processDailyEth(lvl, 0, entropy, traitIds, shareBps, bucketCounts, isFinalDay, SPLIT_CALL2, true)` where `ethPool=0` (because CALL2 reads `resumeEthPool` internally at line 1193-1195).

**3. Can any function be called between CALL1 and CALL2 that modifies the stored state?**

Between CALL1 and CALL2, `advanceGame()` returns to the caller. On the next `advanceGame()` call:
- The `resumeEthPool != 0` check at AdvanceModule line 406 routes directly to `payDailyJackpot(true, lvl, rngWord)` which enters the resume path.
- No other function can modify `resumeEthPool` because it is `internal` in DegenerusGameStorage and only written by `_processDailyEth`.
- No other function modifies `dailyJackpotTraitsPacked` between calls because it is only written by `_syncDailyWinningTraits` (called once at the start of each day's jackpot).
- `rngWordByDay[day]` is immutable once set.
- The winning traits, level, and RNG word are deterministic -- same day produces same values.

**HOWEVER:** Between CALL1 and CALL2, a player COULD call `purchase()`, `placeDegeneretteBet()`, etc. These functions modify:
- `claimablePool` (via degenerette payouts) -- but `_processDailyEth` only WRITES to `claimablePool` via `+= liabilityDelta`, so a concurrent write is additive and order-independent.
- `prizePoolsPacked` (via mint payments) -- but `_processDailyEth` does NOT read or write pool values.
- `ticketQueue` (via new purchases) -- but `_processDailyEth` reads `traitBurnTicket[lvl]` (the BURN ticket pool, not the ticket queue). New purchases add to the write-slot ticket queue, not the burn ticket pool.
- `claimableWinnings[player]` -- additive, order-independent.

**4. What happens if CALL2 reverts but CALL1 succeeded?**

If CALL2 reverts (e.g., gas limit hit), `resumeEthPool` remains non-zero. The next `advanceGame()` call will retry CALL2 with the same parameters. `resumeEthPool` is only cleared inside CALL2 at line 1194-1195: `resumeEthPool = 0`. Since CALL2 operates on a fresh `ethPool` read from `resumeEthPool`, and the winners for mid buckets were not yet paid, the retry will correctly process the remaining buckets.

The CALL1 winners (largest + solo buckets) have already been paid and their `claimableWinnings` incremented. CALL2 processes DIFFERENT buckets (the mid buckets), so there is no double-payment risk.

**5. Verdict: SAFE** -- The two-call split is correctly designed:
- CALL1 processes largest + solo buckets, stores `resumeEthPool` as checkpoint.
- CALL2 processes mid buckets, reads `resumeEthPool`, clears it.
- State between calls is deterministic (traits/level/RNG immutable, resumeEthPool only writable by _processDailyEth).
- Retry-safe: if CALL2 reverts, resumeEthPool persists for retry.
- No inter-call state corruption possible: concurrent writes are additive and to different slots than _processDailyEth reads.

## Per-Function Verdicts

### Module Contracts

#### DegenerusGameAdvanceModule.sol

| Function | Visibility | State Writes | State Corruption Verdict | Composition Risk | Composition Verdict | Notes |
|----------|-----------|--------------|--------------------------|------------------|---------------------|-------|
| advanceGame | external | slot 0 fields (purchaseStartDay, dailyIdx, rngLockedFlag, jackpotPhaseFlag, lastPurchaseDay, compressedJackpotFlag, gameOverPossible, phaseTransitionActive, ticketsFullyProcessed, jackpotCounter, level, ticketWriteSlot, prizePoolFrozen), slot 1 (currentPrizePool, claimablePool), prizePoolsPacked, yieldAccumulator, rngWordByDay, ticketQueue, ticketsOwedPacked, levelPrizePool, levelDgnrsAllocation, presaleStatePacked | SAFE | Orchestrates all module delegatecalls sequentially; single-threaded execution within transaction | SAFE | All state transitions are sequential; do-while(false) pattern ensures single path per call |
| _handleGameOverPath | private | gameOver, gameOverStatePacked via delegatecall to GameOverModule, rngLockedFlag | SAFE | Calls GameOverModule.handleGameOverDrain and handleFinalSweep via delegatecall | SAFE | gameOver=true gate prevents re-entry; _unlockRng after delegatecall |
| _rewardTopAffiliate | private | levelDgnrsAllocation[lvl] | SAFE | External calls to affiliate.affiliateTop (read-only) and dgnrs.transferFromPool | SAFE | Write after external reads follows CEI; state write is independent |
| _distributeYieldSurplus | private | (delegates to JackpotModule.distributeYieldSurplus) | SAFE | Delegatecall; operates in Game's storage context | SAFE | Runs BEFORE pool consolidation; see distributeYieldSurplus analysis below |
| _consolidatePoolsAndRewardJackpots | private | prizePoolsPacked, currentPrizePool, yieldAccumulator, claimablePool, claimableWinnings (via self-calls) | SAFE | Memory-batch pattern with self-calls to runBafJackpot/runDecimatorJackpot and external call to coinflip.creditFlip | SAFE | Fully analyzed in Pool Consolidation Write-Batch Integrity section above |
| rngGate | internal | rngWordByDay[day], rngWordCurrent, rngRequestTime, dailyIdx, purchaseStartDay, lootboxRngWordByIndex, lootboxRngPacked | SAFE | External calls to coinflip.processCoinflipPayouts, quests.rollDailyQuest, sdgnrs.resolveRedemptionPeriod | SAFE | All external calls occur AFTER rngWordByDay[day] is committed; state cannot be corrupted by callback |
| _gameOverEntropy | private | rngWordByDay[day], rngWordCurrent, rngRequestTime, lootboxRngWordByIndex | SAFE | Same external calls as rngGate plus VRF fallback path | SAFE | Fallback entropy uses historical VRF words (non-manipulable) |
| _requestRng | private | vrfRequestId, rngWordCurrent, rngRequestTime, level (increment), rngLockedFlag, decWindowOpen, lootboxRngPacked | SAFE | External call to vrfCoordinator.requestRandomWords, dgnrs.transferFromPool, charityResolve.pickCharity, quests.rollLevelQuest | SAFE | Level increment and related writes happen atomically before external calls |
| requestLootboxRng | external | lootboxRngPacked, vrfRequestId, rngWordCurrent, rngRequestTime, ticketWriteSlot (via _swapTicketSlot) | SAFE | External call to vrfCoordinator.requestRandomWords | SAFE | rngLockedFlag check at entry prevents conflict with daily path; packed field writes are sequential |
| rawFulfillRandomWords | external | rngWordCurrent, rngRequestTime, lootboxRngWordByIndex | SAFE | No external calls in fulfillment handler | SAFE | VRF callback writes are isolated from game flow |
| _enforceDailyMintGate | private view | (none -- view) | SAFE | Reads mintPacked_ (HAS_DEITY_PASS, FROZEN_UNTIL_LEVEL, DAY), external call to vault.isVaultOwner | SAFE | Pure gate; no state mutation |
| _evaluateGameOverAndTarget | private | gameOverPossible | SAFE | No external calls; pure arithmetic on cached pool values | SAFE | Single bool write based on drip projection |
| _wadPow | private pure | (none -- pure) | SAFE | No external interactions | SAFE | Fixed-point math library function |
| _projectedDrip | private pure | (none -- pure) | SAFE | No external interactions | SAFE | Geometric series computation |

#### DegenerusGameJackpotModule.sol

| Function | Visibility | State Writes | State Corruption Verdict | Composition Risk | Composition Verdict | Notes |
|----------|-----------|--------------|--------------------------|------------------|---------------------|-------|
| distributeYieldSurplus | external | claimableWinnings[VAULT/SDGNRS/GNRUS], claimablePool, yieldAccumulator | SAFE | Uses _addClaimableEth which may trigger auto-rebuy writing to prizePoolsPacked and ticketQueue | SAFE | Runs BEFORE _consolidatePoolsAndRewardJackpots; pool writes from auto-rebuy here will be overwritten by the subsequent memory batch, but the amounts stay in memFuture/memNext (see pool consolidation analysis) |
| payDailyJackpot | external | currentPrizePool, claimablePool, claimableWinnings, dailyJackpotTraitsPacked, jackpotCounter, dailyJackpotCoinTicketsPending, dailyTicketBudgetsPacked, resumeEthPool, prizePoolsPacked (nextPrizePool via lootbox), ticketQueue, ticketsOwedPacked, whalePassClaims | SAFE | Multiple internal calls to _processDailyEth, _runEarlyBirdLootboxJackpot, external calls to coinflip.creditFlip via _awardDailyCoinToTraitWinners | SAFE | Two-call split pattern verified safe (see Two-Call Split analysis) |
| payDailyJackpotCoinAndTickets | external | ticketQueue, ticketsOwedPacked, dailyJackpotCoinTicketsPending | SAFE | External calls to coinflip.creditFlip for coin winners | SAFE | Reads from immutable daily state (traits, budgets); coin credits are after ticket writes |
| runBafJackpot | external | claimableWinnings, claimablePool (via _addClaimableEth), whalePassClaims, ticketQueue, ticketsOwedPacked | SAFE | Self-call guard (msg.sender == address(this)); external call to jackpots.runBafJackpot (read-only for winner selection) | SAFE | Returns claimableDelta; non-claimable portions stay in caller's memFuture implicitly |
| _processDailyEth | private | claimableWinnings (via _addClaimableEth), claimablePool, resumeEthPool, prizePoolsPacked (via auto-rebuy), ticketQueue (via auto-rebuy), whalePassClaims | SAFE | Calls _handleSoloBucketWinner, _payNormalBucket which call _addClaimableEth | SAFE | Split mode routing verified; CALL1 and CALL2 process disjoint bucket sets |
| _resumeDailyEth | private | Same as _processDailyEth CALL2 | SAFE | Reconstructs parameters from stored state, calls _processDailyEth with SPLIT_CALL2 | SAFE | Deterministic reconstruction from immutable daily state |
| _handleSoloBucketWinner | private | claimableWinnings, claimablePool, whalePassClaims, levelDgnrsAllocation (via dgnrs.transferFromPool) | SAFE | External calls to dgnrs.transferFromPool, dgnrs.poolBalance | SAFE | Solo bucket winner processing; DGNRS reward on final day only |
| _payNormalBucket | private | claimableWinnings, claimablePool, prizePoolsPacked (via auto-rebuy), ticketQueue (via auto-rebuy) | SAFE | Uses _addClaimableEth for each winner | SAFE | Standard bucket payout loop |
| _addClaimableEth | private | claimableWinnings (via _creditClaimable), autoRebuyState (read), prizePoolsPacked (via _setFuturePrizePool/_setNextPrizePool if auto-rebuy), ticketQueue (if auto-rebuy) | SAFE | No external calls (pure storage mutations) | SAFE | Auto-rebuy pool writes may be overwritten by pool consolidation memory batch; this is by design |
| _randTraitTicket | private | (none -- pure selection) | SAFE | No external calls; keccak256-based deterministic selection | SAFE | Merged with _randTraitTicketWithIndices; per-winner keccak indexing |
| _rollWinningTraits | private | (none -- pure computation) | SAFE | No external calls | SAFE | Random trait + hero override |
| _runEarlyBirdLootboxJackpot | private | ticketQueue, ticketsOwedPacked | SAFE | No external calls | SAFE | Ticket queueing only |
| _distributeLootboxAndTickets | private | prizePoolsPacked (nextPrizePool), ticketQueue, ticketsOwedPacked | SAFE | No external calls | SAFE | Pool increment + ticket distribution |
| _awardDailyCoinToTraitWinners | private | (none directly -- via external coinflip.creditFlip calls) | SAFE | External calls to coinflip.creditFlip per winner | SAFE | BURNIE credits after winner selection; no state dependency on creditFlip return |
| runTerminalJackpot | external | claimablePool, claimableWinnings | SAFE | msg.sender == GAME guard; calls _processDailyEth with SPLIT_NONE | SAFE | Used only by GameOverModule during handleGameOverDrain |

#### DegenerusGameMintModule.sol

| Function | Visibility | State Writes | State Corruption Verdict | Composition Risk | Composition Verdict | Notes |
|----------|-----------|--------------|--------------------------|------------------|---------------------|-------|
| purchase | external | mintPacked_, prizePoolsPacked (nextPrizePool, futurePrizePool), lootboxRngPacked (pending ETH/BURNIE), presaleStatePacked (mint ETH), ticketQueue, ticketsOwedPacked, lootboxEth/lootboxBurnie/lootboxEthBase, lootboxBaseLevelPacked, lootboxDay, lootboxEvScorePacked | SAFE | External calls to affiliate.payAffiliate, quests.handlePurchase/handleMint, coinflip.creditFlip | SAFE | All storage writes before external calls (CEI); lootbox pending accumulation uses packed _lrWrite |
| purchaseCoin | external | Same as purchase minus ETH pool writes (BURNIE-denominated) | SAFE | External calls to coin.burnForCoinflip, quests.handlePurchase | SAFE | BURNIE path; pool writes use packed helpers |
| purchaseBurnieLootbox | external | lootboxRngPacked, lootboxBurnie, ticketQueue (if gameOverPossible redirect) | SAFE | No external calls | SAFE | gameOverPossible flag redirect to far-future tickets |
| recordMintData | external | mintPacked_ (multiple fields via BitPackingLib) | SAFE | No external calls | SAFE | Pure mintPacked_ manipulation; affiliate bonus cache write piggybacks on existing SSTORE |
| processTicketBatch | external | ticketQueue (pop from read slot), ticketCursor, ticketLevel, traitBurnTicket (push), ticketsOwedPacked | SAFE | No external calls (moved from JackpotModule) | SAFE | Ticket processing is isolated; reads from read slot, writes to burn ticket pool |
| _raritySymbolBatch | private | (none -- pure assembly computation, returns to processTicketBatch) | SAFE | No external calls; LCG PRNG in assembly | SAFE | Deterministic trait generation from entropy |

#### DegenerusGameWhaleModule.sol

| Function | Visibility | State Writes | State Corruption Verdict | Composition Risk | Composition Verdict | Notes |
|----------|-----------|--------------|--------------------------|------------------|---------------------|-------|
| purchaseWhaleBundle | external | mintPacked_, ticketQueue, ticketsOwedPacked, lootboxRngPacked (pending ETH), presaleStatePacked, lootboxEth/lootboxEthBase/lootboxBaseLevelPacked/lootboxDay/lootboxEvScorePacked | SAFE | No external calls from WhaleModule itself (delegatecalled from Game which handles msg.value) | SAFE | Multiple packed field writes are sequential |
| purchaseLazyPass | external | mintPacked_, ticketQueue, ticketsOwedPacked, lootboxRngPacked | SAFE | No external calls | SAFE | Uses _activate10LevelPass helper |
| purchaseDeityPass | external | mintPacked_ (HAS_DEITY_PASS_SHIFT), deityPassPurchasedCount, deityPassPaidTotal, deityPassOwners, deityPassSymbol, deityBySymbol, lootboxRngPacked, ticketQueue, ticketsOwedPacked | SAFE | External calls to dgnrs.transferFromPool (DGNRS reward), DeityPass.mint (NFT) | SAFE | mintPacked_ HAS_DEITY_PASS bit set BEFORE external calls; NFT mint is last action |
| claimWhalePass | external | whalePassClaims (clear), mintPacked_ (via _applyWhalePassStats), ticketQueue, ticketsOwedPacked | SAFE | No external calls | SAFE | Clear-before-award pattern; gameOver check at entry |

#### DegenerusGameDecimatorModule.sol

| Function | Visibility | State Writes | State Corruption Verdict | Composition Risk | Composition Verdict | Notes |
|----------|-----------|--------------|--------------------------|------------------|---------------------|-------|
| recordDecimatorBurn | external | decimator burn tracking mappings | SAFE | No external calls from this function | SAFE | Pure burn record tracking |
| runDecimatorJackpot | external | decimator resolution state | SAFE | Self-call from Game; external call to jackpots contract for resolution | SAFE | Returns refund amount to caller |
| claimDecimatorJackpot | external | claimableWinnings (via _creditClaimable), claimablePool (uint128) | SAFE | No external calls; uses _creditClaimable directly (auto-rebuy removed) | SAFE | Simplified from v5.0 -- no auto-rebuy pool writes |
| recordTerminalDecBurn | external | terminal decimator burn entries | SAFE | No external calls | SAFE | Burns blocked at <=7 days |
| claimTerminalDecimatorJackpot | external | claimableWinnings (via _creditClaimable), claimablePool | SAFE | No external calls | SAFE | prizePoolFrozen check removed; uses day-index arithmetic |
| _terminalDecMultiplierBps | private view | (none -- view) | SAFE | No external calls | SAFE | Linear formula: 20x at day 120 to 1x at day 10 |
| _terminalDecDaysRemaining | private view | (none -- view) | SAFE | No external calls | SAFE | Day-index arithmetic (purchaseStartDay + deadline) |
| _awardDecimatorLootbox | private | whalePassClaims, claimableWinnings, ticketQueue, ticketsOwedPacked | SAFE | No external calls | SAFE | Inline whale pass calculation replaces _queueWhalePassClaimCore for large amounts |

#### DegenerusGameDegeneretteModule.sol

| Function | Visibility | State Writes | State Corruption Verdict | Composition Risk | Composition Verdict | Notes |
|----------|-----------|--------------|--------------------------|------------------|---------------------|-------|
| placeDegeneretteBet | external | bet state, claimablePool (uint128), lootboxRngPacked (pending ETH/BURNIE via _lrWrite), prizePoolsPacked (via _collectBetFunds pool allocations) | SAFE | External calls to quests.handleDegenerette, coinflip.creditFlip | SAFE | _collectBetFunds modifies packed state before external calls |
| resolveBets | external | bet state, claimableWinnings, claimablePool | SAFE | No external calls within resolution | SAFE | Resolution reads immutable RNG words |
| _collectBetFunds | private | claimablePool (uint128 deduction), lootboxRngPacked (pending accumulation via _lrWrite) | SAFE | No external calls | SAFE | Packed milli-ETH/whole-BURNIE encoding uses _lrWrite with correct masks |
| _placeDegeneretteBetCore | private | bet state, activity score via _playerActivityScore (read-only) | SAFE | External call to quests.handleDegenerette | SAFE | Quest call after bet state committed |
| _distributePayout | private | claimableWinnings, claimablePool (uint128) | SAFE | External call to dgnrs.transferFromPool (for sDGNRS payouts) | SAFE | claimablePool narrowed to uint128; write after computation |

#### DegenerusGameGameOverModule.sol

| Function | Visibility | State Writes | State Corruption Verdict | Composition Risk | Composition Verdict | Notes |
|----------|-----------|--------------|--------------------------|------------------|---------------------|-------|
| handleGameOverDrain | external | gameOver, gameOverStatePacked (GO_TIME, GO_JACKPOT_PAID), currentPrizePool, prizePoolsPacked, yieldAccumulator, claimableWinnings, claimablePool | SAFE | External calls to charityGameOver.burnAtGameOver, dgnrs.burnAtGameOver; self-calls to runTerminalDecimatorJackpot, runTerminalJackpot | SAFE | gameOver=true set before external calls; defense-in-depth RNG check gates ALL side effects |
| handleFinalSweep | external | gameOverStatePacked (GO_SWEPT), claimablePool (zeroed) | SAFE | External calls to admin.shutdownVrf (fire-and-forget), stETH transfer, ETH transfer | SAFE | 30-day delay enforced; finalSwept flag prevents double-sweep |
| _sendToVault | private | (no storage writes -- pure ETH/stETH transfers) | SAFE | External ETH and stETH transfers to SDGNRS, VAULT, GNRUS (33/33/34 split) | SAFE | _sendStethFirst sends stETH first (ERC20), then ETH (raw call) |
| _sendStethFirst | private | (no storage writes) | SAFE | stETH.transfer then raw ETH call | SAFE | CEI: no state changes after transfers |

#### DegenerusGameLootboxModule.sol

| Function | Visibility | State Writes | State Corruption Verdict | Composition Risk | Composition Verdict | Notes |
|----------|-----------|--------------|--------------------------|------------------|---------------------|-------|
| openLootbox | external | lootboxEth/lootboxBurnie (clear), claimableWinnings, claimablePool, boon state (via BoonModule delegatecall), ticketQueue, ticketsOwedPacked, presaleStatePacked | SAFE | External calls to coinflip.creditFlip; delegatecall to BoonModule | SAFE | Multi-boon support; lootbox state cleared before resolution |
| openBurnieLootbox | external | lootboxBurnie (clear), boon state, ticketQueue (if gameOverPossible redirect) | SAFE | External calls to coinflip.creditFlip; delegatecall to BoonModule | SAFE | gameOverPossible flag for endgame redirect |
| deityBoonSlots | external | deityBoonDay, deityBoonUsedMask | SAFE | No external calls | SAFE | Day-based reset and slot assignment |
| issueDeityBoon | external | boon state via BoonModule delegatecall | SAFE | Delegatecall to BoonModule | SAFE | Deity boon application |
| _rollLootboxBoons | private | boon state via nested BoonModule delegatecall | SAFE | Delegatecall | SAFE | Multi-boon per player; upgrade semantics |

#### DegenerusGameBoonModule.sol

| Function | Visibility | State Writes | State Corruption Verdict | Composition Risk | Composition Verdict | Notes |
|----------|-----------|--------------|--------------------------|------------------|---------------------|-------|
| consumeCoinflipBoon | external | boon packed state (clears coinflip boon) | SAFE | No external calls | SAFE | State clear then emit BoonConsumed pattern |
| consumePurchaseBoost | external | boon packed state (clears purchase boon) | SAFE | No external calls | SAFE | State clear then emit BoonConsumed pattern |
| consumeDecimatorBoost | external | boon packed state (clears decimator boon) | SAFE | No external calls | SAFE | State clear then emit BoonConsumed pattern |
| consumeActivityBoon | external | boon packed state, quest streak bonus | SAFE | No external calls from BoonModule | SAFE | State clear then emit BoonConsumed pattern |

#### DegenerusGameMintStreakUtils.sol

| Function | Visibility | State Writes | State Corruption Verdict | Composition Risk | Composition Verdict | Notes |
|----------|-----------|--------------|--------------------------|------------------|---------------------|-------|
| _playerActivityScore | internal view | (none -- view) | SAFE | External call to questView.playerQuestStates (read-only) | SAFE | 5-component scoring: mint streak, mint count, quest streak, affiliate bonus, deity/whale pass |

#### DegenerusGamePayoutUtils.sol

| Function | Visibility | State Writes | State Corruption Verdict | Composition Risk | Composition Verdict | Notes |
|----------|-----------|--------------|--------------------------|------------------|---------------------|-------|
| _creditClaimable | internal | claimableWinnings[beneficiary] | SAFE | No external calls | SAFE | Unchecked add; uint256 overflow impossible with real ETH amounts |
| _queueWhalePassClaimCore | internal | whalePassClaims[winner], claimableWinnings[winner] (for remainder), claimablePool (uint128 for remainder) | SAFE | No external calls | SAFE | claimablePool uint128 cast is safe (bounded by available ETH) |

### Core Contracts

#### DegenerusGame.sol

| Function | Visibility | State Writes | State Corruption Verdict | Composition Risk | Composition Verdict | Notes |
|----------|-----------|--------------|--------------------------|------------------|---------------------|-------|
| advanceGame | external | (delegatecall to AdvanceModule) | SAFE | Single delegatecall entry point | SAFE | See AdvanceModule analysis |
| purchase | external | (delegatecall to MintModule) | SAFE | Delegatecall | SAFE | See MintModule analysis |
| reverseFlip | external (inline) | totalFlipReversals, prizePoolsPacked (futurePrizePool) | SAFE | External call to coinflip.depositCoinflip | SAFE | Compounding nudge cost; rngLockedFlag guard |
| _processMintPayment | private | claimablePool (uint128 deduction), prizePoolsPacked (nextPrizePool, futurePrizePool), pendingPools (if frozen) | SAFE | No external calls | SAFE | claimablePool cast to uint128; pool allocation math |
| _claimWinningsInternal | private | claimableWinnings[player] (clear), claimablePool (uint128 deduction) | SAFE | External ETH/stETH transfers AFTER state updates | SAFE | finalSwept via _goRead packed field; CEI pattern |
| claimAffiliateDgnrs | external | affiliateDgnrsClaimedBy, levelDgnrsClaimed, mintPacked_ (HAS_DEITY_PASS read only) | SAFE | External calls to dgnrs.transferFromPool, coinflip.creditFlip | SAFE | Claim tracking updates before external calls |
| runBafJackpot | external | (delegatecall to JackpotModule.runBafJackpot) | SAFE | Delegatecall | SAFE | Self-call routing; see JackpotModule analysis |
| setLootboxRngThreshold | external | lootboxRngPacked (threshold field) | SAFE | No external calls; vault.isVaultOwner gate | SAFE | Single packed field write |
| hasDeityPass | external view | (none -- view) | SAFE | No state mutation | SAFE | Reads mintPacked_ HAS_DEITY_PASS_SHIFT |
| mintPackedFor | external view | (none -- view) | SAFE | No state mutation | SAFE | Raw mintPacked_ read |
| gameOverTimestamp | external view | (none -- view) | SAFE | No state mutation | SAFE | Reads gameOverStatePacked GO_TIME |

#### DegenerusAdmin.sol

| Function | Visibility | State Writes | State Corruption Verdict | Composition Risk | Composition Verdict | Notes |
|----------|-----------|--------------|--------------------------|------------------|---------------------|-------|
| proposeFeedSwap | external | FeedProposal state, feedProposalCount | SAFE | External call to sdgnrs.votingSupply (read-only) | SAFE | Proposal struct repacked 3 slots; no overlap |
| voteFeedSwap | external | FeedProposal state (votes), VRF coordinator swap (if threshold met) | SAFE | External call to sdgnrs.votingSupply, sdgnrs.balanceOf | SAFE | _applyVote shared helper; zero-weight poke pattern for stale proposal cleanup |
| vote | external | Proposal state (votes, execution) | SAFE | External calls to sdgnrs.votingSupply, sdgnrs.balanceOf | SAFE | Proposal struct repacked (uint40 weights); _resolveThreshold shared logic |
| onTokenTransfer | external | (routes to coinflipReward.creditFlip) | SAFE | External call to coinflip.creditFlip; reads mintPrice from game | SAFE | LINK purchase reward routing |

#### DegenerusAffiliate.sol

| Function | Visibility | State Writes | State Corruption Verdict | Composition Risk | Composition Verdict | Notes |
|----------|-----------|--------------|--------------------------|------------------|---------------------|-------|
| payAffiliate | external | affiliate balances, leaderboard entries, referral state | SAFE | External calls to quests.handleAffiliate, coinflip.creditFlip | SAFE | 75/20/5 roll; leaderboard tracking post-taper; quest routing direct |
| registerAffiliateCode | external | affiliate code registry | SAFE | No external calls | SAFE | Address-range rejection prevents code collision |
| _resolveCodeOwner | private view | (none -- view) | SAFE | No external calls | SAFE | Custom lookup then address-derived default |
| affiliateBonusPoints | external view | (none -- view) | SAFE | No external calls | SAFE | Tiered rate: 4pts/ETH first 5 ETH, 1.5pts/ETH next 20 |

#### DegenerusQuests.sol

| Function | Visibility | State Writes | State Corruption Verdict | Composition Risk | Composition Verdict | Notes |
|----------|-----------|--------------|--------------------------|------------------|---------------------|-------|
| rollDailyQuest | external | quest state (daily slot, roll, target) | SAFE | No external calls | SAFE | Day parameter uint32; simplified return |
| rollLevelQuest | external | quest state (level quest slot, target) | SAFE | No external calls | SAFE | New function; activated at level transition |
| handleMint | external | quest progress (mint path) | SAFE | External call to coinflip.creditFlip (quest reward) | SAFE | mintPrice parameter added; direct coinflip routing |
| handleLootBox | external | quest progress (lootbox path) | SAFE | External call to coinflip.creditFlip | SAFE | mintPrice parameter added |
| handleDegenerette | external | quest progress (degenerette path) | SAFE | External call to coinflip.creditFlip | SAFE | mintPrice parameter added |
| handleDecimator | external | quest progress (decimator path) | SAFE | External call to coinflip.creditFlip | SAFE | Direct routing (was via BurnieCoin) |
| handleAffiliate | external | quest progress (affiliate path) | SAFE | External call to coinflip.creditFlip | SAFE | Direct routing (was via BurnieCoin) |
| handlePurchase | external | quest progress (unified purchase path) | SAFE | External call to coinflip.creditFlip | SAFE | New: unifies mint+lootbox quest paths |

#### BurnieCoin.sol

| Function | Visibility | State Writes | State Corruption Verdict | Composition Risk | Composition Verdict | Notes |
|----------|-----------|--------------|--------------------------|------------------|---------------------|-------|
| mintForGame | external | BURNIE balances (mint) | SAFE | No external calls | SAFE | Dual caller check: COINFLIP or GAME |
| burnForCoinflip | external | BURNIE balances (burn) | SAFE | No external calls | SAFE | Access: COINFLIP only |
| decimatorBurn | external | BURNIE balances (burn) | SAFE | External calls to game.consumeDecimatorBoon, quests.handleDecimator | SAFE | decWindow returns single bool; level fetched separately |

#### BurnieCoinflip.sol

| Function | Visibility | State Writes | State Corruption Verdict | Composition Risk | Composition Verdict | Notes |
|----------|-----------|--------------|--------------------------|------------------|---------------------|-------|
| creditFlip | external | coinflip state (pending flips per player) | SAFE | No external calls | SAFE | Expanded creditors: GAME+QUESTS+AFFILIATE+ADMIN |
| creditFlipBatch | external | coinflip state (pending flips, batch) | SAFE | No external calls | SAFE | Dynamic arrays replace fixed-3; loop bound = array length |
| depositCoinflip | external | coinflip state, BURNIE balances (via burnForCoinflip) | SAFE | External calls to coin.burnForCoinflip, game.hasDeityPass | SAFE | Auto-rebuy fix: reads claimableStored not mintable |
| _claimInternal | private | coinflip resolution state, BURNIE balances (via coin.mintForGame) | SAFE | External call to coin.mintForGame | SAFE | mintForCoinflip unified into mintForGame |

#### DegenerusStonk.sol

| Function | Visibility | State Writes | State Corruption Verdict | Composition Risk | Composition Verdict | Notes |
|----------|-----------|--------------|--------------------------|------------------|---------------------|-------|
| claimVested | external | DGNRS balances (vested allocation release) | SAFE | No external calls; pure internal _transfer | SAFE | Vesting arithmetic: CREATOR_INITIAL + min(level, 30) * VEST_PER_LEVEL |
| yearSweep | external | DGNRS/sDGNRS balances (burns remaining) | SAFE | External ETH transfers to GNRUS and VAULT (50/50 split) | SAFE | 1-year post-gameover; SweepNotReady/NothingToSweep guards; burns before transfers |

#### StakedDegenerusStonk.sol

| Function | Visibility | State Writes | State Corruption Verdict | Composition Risk | Composition Verdict | Notes |
|----------|-----------|--------------|--------------------------|------------------|---------------------|-------|
| poolTransfer | external | sDGNRS balances (burn on self-win) | SAFE | No external calls | SAFE | Self-win burns instead of no-op; prevents pool imbalance |
| resolveRedemptionPeriod | external | redemption period state (resolved flag, flipDay) | SAFE | No external calls; void return (BURNIE paid on claim) | SAFE | No phantom creditFlip; clean separation of resolution and claim |
| votingSupply | external view | (none -- view) | SAFE | No external calls | SAFE | Excludes this/DGNRS/VAULT from total supply |
| burnAtGameOver | external | burns remaining pool balances | SAFE | No external calls | SAFE | gameOver gate; renamed from burnRemainingPools |

#### DegenerusVault.sol

| Function | Visibility | State Writes | State Corruption Verdict | Composition Risk | Composition Verdict | Notes |
|----------|-----------|--------------|--------------------------|------------------|---------------------|-------|
| gameDegeneretteBet | external | (routes to game.placeDegeneretteBet) | SAFE | External call to game.placeDegeneretteBet | SAFE | Consolidated from 3 currency-specific functions |
| sdgnrsBurn | external | (routes to sDGNRS burn) | SAFE | External call to sdgnrs.burn | SAFE | Vault-held sDGNRS operations |
| sdgnrsClaimRedemption | external | (routes to sDGNRS claim) | SAFE | External call to sdgnrs.claimRedemption | SAFE | Vault-held sDGNRS operations |

#### GNRUS.sol

| Function | Visibility | State Writes | State Corruption Verdict | Composition Risk | Composition Verdict | Notes |
|----------|-----------|--------------|--------------------------|------------------|---------------------|-------|
| transfer | external pure | (reverts TransferDisabled) | SAFE | No state mutation possible | SAFE | Soulbound enforcement |
| transferFrom | external pure | (reverts TransferDisabled) | SAFE | No state mutation possible | SAFE | Soulbound enforcement |
| approve | external pure | (reverts TransferDisabled) | SAFE | No state mutation possible | SAFE | Soulbound enforcement |
| burn | external | balanceOf[burner], totalSupply | SAFE | External calls to game.claimWinnings (if needed), steth.transfer, raw ETH transfer | SAFE | See GNRUS State Integrity section |
| burnAtGameOver | external | balanceOf[address(this)], totalSupply, finalized | SAFE | No external calls (pure balance manipulation) | SAFE | onlyGame guard; finalized flag prevents double-call |
| propose | external | proposals mapping, levelProposalStart, levelProposalCount, hasProposed, creatorProposalCount, levelSdgnrsSnapshot, levelVaultOwner | SAFE | External calls to sdgnrs.votingSupply, sdgnrs.balanceOf, vault.isVaultOwner (all read-only) | SAFE | See GNRUS State Integrity section |
| vote | external | proposals[proposalId].approveWeight/rejectWeight, hasVoted | SAFE | External calls to sdgnrs.balanceOf, vault.isVaultOwner (all read-only) | SAFE | See GNRUS State Integrity section |
| pickCharity | external | levelResolved, currentLevel, balanceOf[address(this)], balanceOf[recipient] | SAFE | No external calls | SAFE | onlyGame guard; see GNRUS State Integrity section |

## Cross-Module Composition Analysis

### State-Mutation Chains (SM-01 through SM-56)

| Chain | Caller -> Callee | Composition Risk | Verdict | Notes |
|-------|-----------------|------------------|---------|-------|
| SM-01 | Game.advanceGame -> AdvanceModule | Sequential orchestration; single delegatecall; all state transitions atomic within transaction | SAFE | AdvanceModule is the sole orchestrator; no parallel state mutation paths |
| SM-02 | AdvanceModule._consolidate... -> JackpotModule.distributeYieldSurplus | Yield surplus adds to claimableWinnings before pool consolidation; pool consolidation memory batch writes afterward | SAFE | distributeYieldSurplus runs BEFORE consolidation; auto-rebuy pool writes from yield distribution are overwritten by consolidation memory batch (by design) |
| SM-03 | AdvanceModule._consolidate... -> Game.runBafJackpot -> JackpotModule | Self-call from memory-batch context; claimableDelta returned; non-claimable stays in memFuture implicitly | SAFE | Fully analyzed in Pool Consolidation section; auto-rebuy pool writes harmlessly overwritten |
| SM-04 | AdvanceModule._rewardTopAffiliate -> DegenerusStonk.transferFromPool | External call for DGNRS transfer; levelDgnrsAllocation write follows | SAFE | Read external (pool balance) then write internal (allocation); no re-entrancy concern |
| SM-05 | AdvanceModule.advanceGame -> DegenerusQuests.rollDailyQuest | Quest state write is isolated; no circular dependency with advanceGame | SAFE | Quest state in separate contract; no game state reads in rollDailyQuest |
| SM-06 | AdvanceModule.advanceGame -> DegenerusQuests.rollLevelQuest | Level quest roll at transition; isolated quest state | SAFE | New function; same isolation as SM-05 |
| SM-07 | AdvanceModule.advanceGame -> GNRUS.pickCharity | GNRUS internal state (currentLevel, balanceOf) updated; no game state dependency | SAFE | onlyGame guard; pickCharity does not read game pools or slots |
| SM-08 | AdvanceModule.advanceGame -> StakedDegenerusStonk.resolveRedemptionPeriod | Void return; no game state modified from sDGNRS callback | SAFE | Phantom creditFlip removed; clean void return |
| SM-09 | AdvanceModule.payDailyJackpot -> JackpotModule | Delegatecall; operates on shared storage; two-call split verified safe | SAFE | See Two-Call Split analysis |
| SM-10 | AdvanceModule.payDailyJackpotCoinAndTickets -> JackpotModule | Delegatecall; reads immutable daily state (traits, budgets) | SAFE | Second phase of daily jackpot; reads from state committed in SM-09 |
| SM-11 | JackpotModule._awardDailyCoinToTraitWinners -> BurnieCoinflip.creditFlip | External call; coinflip state isolated from game pools | SAFE | BURNIE flip credit; no game state read in creditFlip |
| SM-12 | JackpotModule._awardDailyCoinToTraitWinners -> BurnieCoinflip.creditFlipBatch | Dynamic arrays; same isolation as SM-11 | SAFE | creditFlipBatch loops over dynamic arrays; no game state dependency |
| SM-13 | Game.purchase -> MintModule | Delegatecall; mint payment, ticket queueing, lootbox state | SAFE | Sequential within delegatecall; all writes before external calls |
| SM-14 | MintModule.purchase -> DegenerusAffiliate.payAffiliate | External call after mint state committed; affiliate state isolated | SAFE | 75/20/5 roll in isolated contract; game state not modified by affiliate |
| SM-15 | MintModule.purchase -> DegenerusQuests.handlePurchase | External call; quest progress isolated | SAFE | Unified purchase quest path; no game state dependency |
| SM-16 | MintModule.purchase -> DegenerusQuests.handleMint | External call; quest progress isolated | SAFE | Mint-specific quest path |
| SM-17 | MintModule.purchase -> BurnieCoinflip.creditFlip | External call; coinflip state isolated | SAFE | Lootbox flip credit |
| SM-18 | MintModule.processTicketBatch -> Game storage | Delegatecall; ticket queue read/write, trait generation | SAFE | Moved from JackpotModule; same storage operations, same delegatecall context |
| SM-19 | Game.purchaseWhaleBundle -> WhaleModule | Delegatecall; mintPacked_ and ticket queue writes | SAFE | All packed writes sequential; presaleStatePacked check before writes |
| SM-20 | WhaleModule.claimWhalePass -> Game storage | Delegatecall; whalePassClaims clear, mintPacked_ write, ticket range queue | SAFE | Clear-before-award; moved from EndgameModule with identical semantics |
| SM-21 | WhaleModule.purchaseDeityPass -> DegenerusStonk.transferFromPool | External call for DGNRS reward; mintPacked_ HAS_DEITY_PASS set before external call | SAFE | Deity pass bit committed before token transfer |
| SM-22 | Game.placeDegeneretteBet -> DegeneretteModule | Delegatecall; bet state, claimablePool, lootbox pending | SAFE | Packed milli-ETH/whole-BURNIE encoding via _lrWrite; sequential |
| SM-23 | DegeneretteModule._placeDegeneretteBetCore -> DegenerusQuests.handleDegenerette | External call after bet state committed | SAFE | Quest routing direct (was via BurnieCoin) |
| SM-24 | DegeneretteModule._distributePayout -> StakedDegenerusStonk.transferFromPool | External call for sDGNRS payout after claimablePool update | SAFE | Pool deduction before transfer |
| SM-25 | Game.openLootBox -> LootboxModule | Delegatecall; lootbox resolution, boon application, ticket queueing | SAFE | Lootbox state cleared before resolution; multi-boon per player |
| SM-26 | LootboxModule._resolveLootboxCommon -> BurnieCoinflip.creditFlip | External call; coinflip state isolated | SAFE | BURNIE reward for lootbox |
| SM-27 | LootboxModule._rollLootboxBoons -> BoonModule | Nested delegatecall; boon packed state writes | SAFE | Same storage context; upgrade semantics for multi-boon |
| SM-28 | Game.consumeCoinflipBoon -> BoonModule | Delegatecall; clears coinflip boon | SAFE | State clear then emit; no external calls |
| SM-29 | Game.consumeDecimatorBoon -> BoonModule | Delegatecall; clears decimator boon | SAFE | State clear then emit |
| SM-30 | Game.consumePurchaseBoost -> BoonModule | Delegatecall; clears purchase boon | SAFE | State clear then emit |
| SM-31 | BurnieCoin.decimatorBurn -> Game.consumeDecimatorBoon -> BoonModule | External call + delegatecall chain; boon state, BURNIE balances | SAFE | BurnieCoin burns first, then consumes boon; no circular dependency |
| SM-32 | BurnieCoin.decimatorBurn -> DegenerusQuests.handleDecimator | External call after burn; quest progress isolated | SAFE | Direct quest routing |
| SM-33 | Game.recordTerminalDecBurn -> DecimatorModule | Delegatecall; terminal decimator burn entries | SAFE | Burns blocked at <=7 days; pure tracking |
| SM-34 | DecimatorModule.claimDecimatorJackpot -> _creditClaimable | Delegatecall internal; claimableWinnings and claimablePool write | SAFE | Auto-rebuy removed; direct _creditClaimable |
| SM-35 | DecimatorModule._awardDecimatorLootbox -> _queueTicketRange | Delegatecall internal; ticket queue writes | SAFE | Inline whale pass calculation |
| SM-36 | DegenerusAdmin.proposeFeedSwap -> StakedDegenerusStonk.votingSupply | External call (read-only); FeedProposal state write after | SAFE | Proposal struct 3 slots; no overlap |
| SM-37 | DegenerusAdmin.voteFeedSwap -> StakedDegenerusStonk.votingSupply | External call (read-only); vote weight calculation | SAFE | Auto-cancel on feed recovery; _executeFeedSwap voids other proposals |
| SM-38 | DegenerusAdmin.vote -> StakedDegenerusStonk.votingSupply | External call (read-only); VRF swap proposal voting | SAFE | Repacked Proposal struct (uint40 weights); shared helpers |
| SM-39 | DegenerusAdmin.onTokenTransfer -> BurnieCoinflip.creditFlip | External call; LINK purchase reward routing | SAFE | coinflipReward.creditFlip replaces coin routing |
| SM-40 | DegenerusAffiliate.payAffiliate -> DegenerusQuests.handleAffiliate | External call; quest progress isolated | SAFE | Direct routing (was via BurnieCoin) |
| SM-41 | DegenerusAffiliate.payAffiliate -> BurnieCoinflip.creditFlip | External call; coinflip state isolated | SAFE | Affiliate reward as flip credit |
| SM-42 | DegenerusQuests.handleMint -> BurnieCoinflip.creditFlip | External call; quest reward as flip credit | SAFE | Direct routing |
| SM-43 | DegenerusQuests.handleLootBox -> BurnieCoinflip.creditFlip | External call; quest reward | SAFE | Direct routing |
| SM-44 | DegenerusQuests.handleDegenerette -> BurnieCoinflip.creditFlip | External call; quest reward | SAFE | Direct routing |
| SM-45 | DegenerusQuests.handleAffiliate -> BurnieCoinflip.creditFlip | External call; quest reward | SAFE | Direct routing |
| SM-46 | DegenerusQuests.handleDecimator -> BurnieCoinflip.creditFlip | External call; quest reward | SAFE | Direct routing |
| SM-47 | DegenerusQuests.handlePurchase -> BurnieCoinflip.creditFlip | External call; unified purchase quest reward | SAFE | New unified path |
| SM-48 | BurnieCoinflip.depositCoinflip -> BurnieCoin.burnForCoinflip | External call; BURNIE burn | SAFE | Auto-rebuy fix: reads claimableStored not mintable |
| SM-49 | BurnieCoinflip._claimInternal -> BurnieCoin.mintForGame | External call; BURNIE mint | SAFE | mintForCoinflip unified into mintForGame with dual caller check |
| SM-50 | DegenerusVault.gameDegeneretteBet -> Game.placeDegeneretteBet | External call; routes to DegeneretteModule via delegatecall | SAFE | Consolidated from 3 currency-specific functions; same delegatecall chain |
| SM-51 | DegenerusVault.sdgnrsBurn -> StakedDegenerusStonk | External call; sDGNRS burn path | SAFE | New vault operation; isolated sDGNRS state |
| SM-52 | DegenerusVault.sdgnrsClaimRedemption -> StakedDegenerusStonk | External call; redemption claim path | SAFE | New vault operation; isolated sDGNRS state |
| SM-53 | StakedDegenerusStonk.poolTransfer (self-win burn) | Internal; burns sDGNRS on self-win | SAFE | Burns instead of no-op; prevents pool imbalance |
| SM-54 | DegenerusStonk.claimVested | Internal; DGNRS balance transfer | SAFE | New vesting; CREATOR_INITIAL + level-based vesting |
| SM-55 | DegenerusStonk.yearSweep -> GNRUS + DegenerusVault | External ETH transfers (50/50 split) | SAFE | 1-year post-gameover; burns before transfers |
| SM-56 | DegenerusDeityPass.onlyOwner -> DegenerusVault.isVaultOwner | External call (read-only guard) | SAFE | Gate for setRenderer/mint; no state mutation in guard |

### ETH-Flow Chains (EF-01 through EF-20)

| Chain | Path | Composition Risk | Verdict | Notes |
|-------|------|------------------|---------|-------|
| EF-01 | Game.purchase -> MintModule -> _processMintPayment | Pool allocation sequential; claimablePool uint128 deduction safe | SAFE | rngLocked gate prevents conflict with jackpot flow |
| EF-02 | AdvanceModule._consolidate... -> pools | Memory-batch write; no intermediate storage corruption | SAFE | Fully analyzed in Pool Consolidation section |
| EF-03 | AdvanceModule -> distributeYieldSurplus -> claimableWinnings | Yield computed from balance minus obligations; additive to claimable | SAFE | Obligations sum is conserved regardless of pool ETH location |
| EF-04 | JackpotModule.payDailyJackpot -> _processDailyEth -> _addClaimableEth | Two-call split; CALL1/CALL2 process disjoint buckets | SAFE | See Two-Call Split analysis |
| EF-05 | JackpotModule._handleSoloBucketWinner -> _addClaimableEth + whale pass + DGNRS | Solo bucket final-day rewards; whale pass via _queueWhalePassClaimCore | SAFE | DGNRS reward from segregated allocation |
| EF-06 | JackpotModule.runBafJackpot -> _addClaimableEth | Self-call; returns claimableDelta | SAFE | Non-claimable stays in memFuture implicitly |
| EF-07 | DecimatorModule.claimDecimatorJackpot -> _creditClaimable | Direct credit; claimablePool uint128 | SAFE | Auto-rebuy removed; clean path |
| EF-08 | DecimatorModule.claimTerminalDecimatorJackpot -> _creditClaimable | Direct credit; multiplier redesigned | SAFE | <=7 days blocked; linear 20x-1x formula |
| EF-09 | DegeneretteModule._distributePayout -> _creditClaimable | claimablePool uint128 narrowing | SAFE | Bounded by bet amounts |
| EF-10 | GameOverModule.handleGameOverDrain -> terminal jackpots + _creditClaimable | RNG defense-in-depth; all pools zeroed | SAFE | gameOver=true gate; pools zeroed atomically |
| EF-11 | GameOverModule.handleFinalSweep -> _sendToVault -> _sendStethFirst | 33/33/34 split; stETH-first | SAFE | 30-day delay; claimablePool zeroed |
| EF-12 | Game._claimWinningsInternal | claimablePool uint128 deduction; finalSwept via _goRead | SAFE | CEI pattern; external transfer last |
| EF-13 | GNRUS.burn -> game.claimWinnings | Proportional ETH+stETH redemption | SAFE | See GNRUS State Integrity section |
| EF-14 | GNRUS.pickCharity -> GNRUS distribution | 2% of unallocated per level | SAFE | Internal balance transfer; no ETH movement |
| EF-15 | Game.claimAffiliateDgnrs -> coinflip.creditFlip | DGNRS claim + flip credit; PriceLookupLib for price | SAFE | mintPacked_ deity pass check |
| EF-16 | WhaleModule.purchaseWhaleBundle/purchaseLazyPass/purchaseDeityPass | ETH in; presaleStatePacked gate; mintPacked_ deity bit | SAFE | Multiple packed field writes sequential |
| EF-17 | DegeneretteModule._collectBetFunds | lootboxRngPendingEth packed milli-ETH encoding | SAFE | Encoding roundtrip verified in packed field audit |
| EF-18 | StakedDegenerusStonk.burnAtGameOver | Burns remaining pools; gameOver gate | SAFE | Renamed; same semantics |
| EF-19 | DegenerusStonk.yearSweep -> 50/50 GNRUS + VAULT | Post-gameover sweep; burns before transfers | SAFE | SweepNotReady/NothingToSweep guards |
| EF-20 | AdvanceModule.advanceGame -> coinflip.creditFlip | Pool consolidation BURNIE credit; inlined from _creditDgnrsCoinflip | SAFE | External call after pool memory batch |

### RNG Chains (RNG-01 through RNG-11)

| Chain | Request/Consumer | Composition Risk | Verdict | Notes |
|-------|-----------------|------------------|---------|-------|
| RNG-01 | AdvanceModule._requestRng -> rawFulfillRandomWords -> rngGate | VRF request/fulfill lifecycle; rngLockedFlag mutual exclusion | SAFE | Gap day backfill via keccak; purchaseStartDay extended |
| RNG-02 | requestLootboxRng -> _finalizeLootboxRng | Packed index advance; midDay ticket swap; VRF request | SAFE | rngLockedFlag blocks concurrent daily/lootbox RNG |
| RNG-03 | JackpotModule._randTraitTicket | Derives from daily word via keccak; merged indexing | SAFE | Per-winner keccak prevents index collision |
| RNG-04 | JackpotModule._runJackpotEthFlow | Fixed [20,12,6,1] bucket counts; entropy rotation | SAFE | Deterministic bucket assignment from VRF word |
| RNG-05 | JackpotModule.payDailyJackpot carryover | 0.5% futurePool as tickets; keccak modulo source offset | SAFE | Random source level [1..4]; ticket-only (no ETH) |
| RNG-06 | DegeneretteModule._placeDegeneretteBetCore | Resolved via daily RNG word; activity score from _lrRead | SAFE | lootboxRngIndex packed read |
| RNG-07 | MintModule._raritySymbolBatch | LCG PRNG in assembly; derives from lootbox word | SAFE | Moved from JackpotModule; same algorithm |
| RNG-08 | AdvanceModule._gameOverEntropy | Fallback prevrandao + historical VRF; reverts RngNotReady | SAFE | Only gameover path; historical words non-manipulable |
| RNG-09 | GameOverModule.handleGameOverDrain | Daily word or _gameOverEntropy | SAFE | Defense-in-depth: reverts if funds > 0 but word unavailable |
| RNG-10 | LootboxModule._deityDailySeed/_deityBoonForSlot | Derives from daily word; day parameter uint32 | SAFE | Deity boon generation |
| RNG-11 | JackpotModule._rollWinningTraits/_applyHeroOverride | Derives from daily word; simplified | SAFE | Random + hero override; renamed from _getWinningTraits |

### Read-Only Chains (RO-01 through RO-12)

| Chain | Caller -> Data | Composition Risk | Verdict | Notes |
|-------|---------------|------------------|---------|-------|
| RO-01 | AdvanceModule._enforceDailyMintGate -> mintPacked_ | HAS_DEITY_PASS_SHIFT replaces deityPassCount mapping | SAFE | View-only; correct shift/mask |
| RO-02 | AdvanceModule -> PriceLookupLib.priceForLevel | Library call (pure); replaces price storage variable | SAFE | No state; deterministic |
| RO-03 | JackpotModule._calcDailyCoinBudget -> PriceLookupLib | Library call (pure) | SAFE | Same as RO-02 |
| RO-04 | MintModule.recordMintData -> BitPackingLib (affiliate bonus cache) | Reads cached affiliate bonus from bits 185-214 | SAFE | Piggybacks on existing SSTORE; no extra reads |
| RO-05 | WhaleModule._purchaseWhaleBundle -> _psRead(presaleStatePacked) | Packed presale state read | SAFE | Correct shift/mask verified |
| RO-06 | LootboxModule.openBurnieLootbox -> gameOverPossible | Bool flag read for endgame redirect | SAFE | Replaces timestamp-based cutoff |
| RO-07 | DegenerusAdmin.proposeVrfSwap/vote -> StakedDegenerusStonk.votingSupply | External call (read-only); replaces circulatingSupply | SAFE | Excludes pools/wrapper/vault |
| RO-08 | GNRUS.propose/vote -> StakedDegenerusStonk.votingSupply | External call (read-only); sDGNRS voting weight | SAFE | Governance threshold check |
| RO-09 | BurnieCoinflip.depositCoinflip -> DegenerusGame.hasDeityPass | External call (read-only); replaces deityPassCountFor | SAFE | mintPacked_ bit check |
| RO-10 | DecimatorModule._terminalDecDaysRemaining -> purchaseStartDay + deadline | Day-index arithmetic (replaces timestamp) | SAFE | uint32 arithmetic; no overflow risk |
| RO-11 | DegenerusGame.claimAffiliateDgnrs -> PriceLookupLib + mintPacked_ | Library call + packed read | SAFE | Price + deity pass for DGNRS claim |
| RO-12 | GameTimeLib.currentDayIndex/currentDayIndexAt | Library call (view); uint32 day index | SAFE | Narrowed from uint48; no overflow |

## GNRUS State Integrity (New Contract)

### 1. Soulbound enforcement: Can transfer/transferFrom/approve be bypassed?

**Analysis:** All three functions are declared `external pure` and unconditionally `revert TransferDisabled()`. There is no fallback function that could handle token transfer selectors. The `receive()` function only accepts ETH (no calldata). There are no delegatecall patterns that could bypass the revert. The only way GNRUS balances change is via:
- `_mint` (called once in constructor, mints to `address(this)`)
- `burn` (called by holder, decrements their balance)
- `burnAtGameOver` (called by game, decrements `address(this)` balance)
- `pickCharity` (called by game, transfers from `address(this)` to recipient)

All four paths are correctly guarded. No bypass exists.

**Verdict: SAFE**

### 2. Proportional burn math: Can rounding errors accumulate to drain more ETH than allocated?

**Analysis:** The burn calculation at line 301:
```
uint256 owed = ((ethBal + stethBal + claimable) * amount) / supply;
```

This computes the proportional share. Because Solidity division truncates, `owed` is always <= the true proportional share. Repeated burns by the same user with small amounts would each truncate downward, so total extracted <= total backing.

**Edge case -- last-holder sweep:** Lines 291-293 check if `burnerBal == amount` or `supply - balanceOf[address(this)] == amount`. If so, `amount = burnerBal` (sweeps full balance). This means the last holder gets everything remaining after all intermediate truncations. The `owed` calculation still uses `supply` (total supply before burn), so the last holder's `owed` is `(backing * burnerBal) / supply`. Since they hold all external GNRUS, this equals the full backing (minus rounding on the division). The 1-wei dust (from `if (claimable > 1) { claimable -= 1; }`) prevents the edge case of claiming the exact last wei of backing.

**Attack vector checked:** Can a user split their GNRUS across multiple accounts and claim more total? No, because each burn computes `(backing * amount) / supply` where `supply` decreases with each burn. The sum of payouts from N sequential burns of `amount/N` each is at most equal to one burn of `amount` (due to truncation on each sub-burn).

**Verdict: SAFE** -- rounding always truncates in favor of the contract; no accumulation attack possible.

### 3. Governance state: Can a proposal be double-counted or a vote be replayed?

**Analysis:**
- **Double proposal:** `hasProposed[level][proposer]` prevents non-creator addresses from proposing twice per level. Creator (vault owner) has `creatorProposalCount[level]` capped at `MAX_CREATOR_PROPOSALS=5`.
- **Vote replay:** `hasVoted[level][voter][proposalId]` prevents voting on the same proposal twice. Voters CAN vote on different proposals within the same level (intended behavior).
- **Cross-level replay:** `proposalId` is a global monotonic counter (`proposalCount++`). Level resolution advances `currentLevel`. Proposing/voting requires `level == currentLevel` (implicit via proposal range check `proposalId >= start && proposalId < start + count`). After `pickCharity`, `currentLevel` increments, making old proposals unreachable.
- **Double resolution:** `levelResolved[level]` flag prevents `pickCharity` from being called twice for the same level.

**Verdict: SAFE** -- all replay/double-count vectors blocked by per-level, per-proposal, per-voter tracking.

### 4. pickCharity distribution: Can the 2% of unallocated be manipulated by timing pickCharity calls?

**Analysis:** `pickCharity` is `onlyGame` -- only callable by the game contract during level transitions in `AdvanceModule._requestRng` (via `charityResolve.pickCharity(level)`). The timing is deterministic: it runs exactly once per level transition, called by `advanceGame()`. No player can trigger it directly.

The distribution amount is `(balanceOf[address(this)] * 200) / 10_000` = 2% of the remaining unallocated GNRUS at the moment of the call. Since the game controls the call timing, and no other function modifies `balanceOf[address(this)]` between levels (only `pickCharity` and `burnAtGameOver` touch it), the distribution amount is deterministic.

**Attack vector checked:** Can a proposer manipulate the sDGNRS snapshot to gain disproportionate voting power? The snapshot is taken on the first proposal of each level (`levelSdgnrsSnapshot[level] = uint48(sdgnrs.votingSupply() / 1e18)`). A voter's weight is `sdgnrs.balanceOf(voter) / 1e18` at vote time (not snapshot time). However, the snapshot is only used for the propose threshold check (`0.5% of snapshot`) and vault vote bonus (`5% of snapshot`). The vote weight itself is dynamic (current balance). This means a voter could accumulate sDGNRS after the snapshot to increase their vote weight. However, this is by design -- the snapshot prevents the threshold from moving, while live voting weight reflects current stakeholder positions. No state corruption concern.

**Verdict: SAFE** -- distribution timing controlled by game; no manipulation vector.

### 5. burnAtGameOver: What happens to pending governance proposals when all unallocated is burned?

**Analysis:** `burnAtGameOver` (line 340-352) sets `finalized = true`, zeros `balanceOf[address(this)]`, and reduces `totalSupply`. After this:
- `pickCharity` will still check `levelResolved[level]`, but `balanceOf[address(this)] == 0` means `distribution = 0`, leading to `LevelSkipped` event. No tokens distributed.
- `propose`/`vote` can still be called (no `finalized` guard), but they are harmless because `pickCharity` will skip distribution.
- `burn` by GNRUS holders is unaffected -- they burn their own balance and claim proportional ETH+stETH.

**Pending proposals at gameover:** If proposals exist for the current level but `pickCharity` is never called (because game is over and no more level transitions), the proposals remain in storage but are permanently unresolvable. This is correct behavior -- no GNRUS is distributed, and holders can still burn for redemption.

**Verdict: SAFE** -- finalization correctly terminates distribution; pending proposals become inert.

## Summary

All 444 changed/new function entries across 39 modified contracts, 4 new contracts (GNRUS, 3 mocks), and 2 deleted contracts have been audited for state corruption and composition attack vulnerabilities.

**Results:**
- **VULNERABLE:** 0
- **SAFE:** All per-function verdicts, all 99 cross-module chain verdicts, all 7 packed state field groups, all 5 EndgameModule redistribution entries, pool consolidation write-batch, two-call split consistency, and GNRUS state integrity (all 5 points)
- **INFO:** 0

**Key architectural findings (all SAFE):**
1. Pool consolidation memory-batch pattern correctly isolates all pool math in memory variables; auto-rebuy pool writes from self-calls are harmlessly overwritten because the corresponding amounts remain in `memFuture` implicitly.
2. Two-call split pattern correctly partitions bucket processing across disjoint sets; resumeEthPool checkpoint enables retry-safe CALL2; inter-call state is deterministic.
3. EndgameModule redistribution preserves state equivalence across all 5 moved functions; delegatecall storage context is identical.
4. GNRUS soulbound enforcement is complete; proportional burn math cannot be exploited via splitting; governance prevents replay at all levels.
5. All 7 packed state groups (slot 0, slot 1, presaleStatePacked, gameOverStatePacked, dailyJackpotTraitsPacked, mintPacked_, lootboxRngPacked) have non-overlapping fields with correct shift/mask pairs.
