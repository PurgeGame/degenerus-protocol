# Phase 219 Plan 02: Theoretical Worst-Case Gas Derivation

**Baseline:** 7,023,530 gas (advanceGame worst case from prior audit)
**Block limit:** 14,000,000 gas (Arbitrum/Base L2 block limit)
**Prior headroom:** 14,000,000 / 7,023,530 = 1.993x

All gas costs derived from EVM opcode tables (Yellow Paper Appendix G, EIP-2929 warm/cold access, EIP-2200 SSTORE costs). No Foundry benchmarks.

---

## 1. Gas Additions (Phase 218 New Costs)

### A. keccak256 Bonus Trait Derivation via `_rollWinningTraits(randWord, true)`

When `isBonus=true` (L1888-1889):
```solidity
uint256 r = isBonus
    ? uint256(keccak256(abi.encodePacked(randWord, BONUS_TRAITS_TAG)))
    : randWord;
```

Per-call opcode breakdown:
| Operation | Opcode(s) | Gas |
|-----------|-----------|-----|
| Read `BONUS_TRAITS_TAG` from code (constant) | PUSH32 (already in bytecode) | 3 |
| `abi.encodePacked(randWord, BONUS_TRAITS_TAG)` memory write | 2x MSTORE (64 bytes total) | 6 (2x3) |
| Memory expansion (already warm from function context) | - | 0 |
| `keccak256` of 64 bytes (2 EVM words) | SHA3: 30 base + 6 per word * 2 = 42 | 42 |
| `uint256(...)` cast | no-op at EVM level | 0 |
| `isBonus` conditional branch | JUMPI | 10 |
| **Per-call total** | | **61** |

Note: When `isBonus=false`, the `else` branch is `r = randWord` (~3 gas for DUP). The conditional JUMPI costs ~10 gas regardless of branch taken. Net overhead for `isBonus=false` calls: ~10 gas (the JUMPI that was not there before). This is negligible and within the noise margin of the prior analysis.

**Worst-case call count per daily drawing:**

The worst case for a single advanceGame transaction is the **jackpot-phase path** (level > 1):

| Call site | Function | `isBonus` | Count |
|-----------|----------|-----------|-------|
| L336 | `payDailyJackpot` (jackpot path) | false | 1 |
| L500 | `payDailyJackpot` bonus derivation block | true | 1 |
| L585 | `payDailyJackpotCoinAndTickets` main | false | 1 |
| L586 | `payDailyJackpotCoinAndTickets` bonus | true | 1 |
| L1158 | `_resumeDailyEth` (two-call split) | false | 1 |
| L1698 | `payDailyCoinJackpot` | true | 1 |

Jackpot-phase worst case: 3 bonus derivation calls (L500, L586, L1698) at 61 gas each = **183 gas**.

The `isBonus=false` calls (L336, L585, L1158) each add ~10 gas for the new JUMPI = **30 gas**.

**Level-1 path** (alternative, NOT additive with jackpot-phase):

| Call site | Function | `isBonus` | Count |
|-----------|----------|-----------|-------|
| L1724 | `emitDailyWinningTraits` main roll | true | 1 |
| L1726 | `emitDailyWinningTraits` salted bonus roll | true | 1 |
| L1698 | first `payDailyCoinJackpot` | true | 1 |
| L1698 | second `payDailyCoinJackpot` (salted rng) | true | 1 |

Level-1 path: 4 bonus derivation calls at 61 gas each = **244 gas**.

The level-1 path has MORE bonus derivation calls but SKIPS the entire `payDailyJackpot` function (a massive ETH distribution). For headroom analysis we use the path with the highest TOTAL gas, which is the jackpot-phase path.

**Bonus derivation subtotal (jackpot-phase worst case): 213 gas** (183 bonus + 30 JUMPI overhead).

### B. DailyWinningTraits Event Emission (LOG4)

Event signature (L97-102):
```solidity
event DailyWinningTraits(
    uint32 indexed day,          // topic 1
    uint32 mainTraitsPacked,     // data
    uint32 bonusTraitsPacked,    // data
    uint24 bonusTargetLevel      // data
);
```

LOG4 opcode gas (Yellow Paper Appendix G):
| Component | Formula | Gas |
|-----------|---------|-----|
| LOG base | 375 | 375 |
| Topic cost | 375 * 4 topics (event sig + day) | Wait -- LOG4 has 4 topics but this event has 1 indexed param |

Correction: `DailyWinningTraits` has 1 indexed parameter (`day`), so the LOG opcode used is **LOG2** (topic 0 = event selector hash, topic 1 = `day`).

LOG2 opcode gas:
| Component | Formula | Gas |
|-----------|---------|-----|
| LOG base | 375 | 375 |
| Topic cost | 375 * 2 topics | 750 |
| Data: 3 ABI-encoded words (mainTraitsPacked, bonusTraitsPacked, bonusTargetLevel each padded to 32 bytes) | 3 * 32 = 96 bytes * 8 gas/byte | 768 |
| Memory for data encoding | 3x MSTORE + offset calcs | ~24 |
| **Per-emission total** | | **1,917** |

Supporting computation before the event (L499-503 in jackpot path):
| Operation | Gas |
|-----------|-----|
| `_rollWinningTraits(randWord, true)` | 61 (already counted in A) |
| `randWord ^ (uint256(lvl) << 192) ^ uint256(COIN_JACKPOT_TAG)` | ~15 (XOR, SHL, XOR) |
| `lvl + 1 + uint24(coinEntropy % 4)` | ~14 (ADD, MOD, ADD) |
| **Supporting computation** | **~29** (not counting the roll, already in A) |

Emission count: exactly 1 per daily drawing (only one code path executes per advanceGame call -- either L503 jackpot path, L517 purchase path, or L1727 level-1 helper).

**Event emission subtotal: 1,946 gas** (1,917 LOG2 + 29 supporting ops).

### C. Level-1 Branch (NEW Path, purchaseLevel == 1 only)

The level-1 branch at AdvanceModule L342-346 is entirely new. It replaces the normal `payDailyJackpot + payDailyCoinJackpot` sequence with:
1. `_emitDailyWinningTraits(1, rngWord, 1)` -- delegatecall
2. `_payDailyCoinJackpot(1, rngWord, 1, 1)` -- first coin jackpot (range [1,1])
3. Salt computation: `keccak256(abi.encodePacked(rngWord, keccak256("BONUS_TRAITS")))`
4. `_payDailyCoinJackpot(1, saltedRng, 2, 5)` -- second coin jackpot (range [2,5])

This path **skips** `payDailyJackpot` entirely (no ETH distribution at level 1, since the prize pool is empty). Therefore:
- Level-1 is NOT the worst case for total gas -- the jackpot-phase path (level > 1) includes full ETH distribution which dominates gas.
- The level-1 branch gas is strictly LOWER than the jackpot-phase path because it skips all ETH logic.

For completeness, the extra salt computation at L345:
| Operation | Gas |
|-----------|-----|
| `keccak256("BONUS_TRAITS")` | Computed at compile time (constant) | 0 |
| `abi.encodePacked(rngWord, ...)` | 2x MSTORE | 6 |
| `keccak256(64 bytes)` | SHA3: 30 + 6*2 = 42 | 42 |
| `uint256(...)` cast | 0 | 0 |
| **Salt total** | | **48** |

This is only incurred on the level-1 path which is not the worst case. Included for completeness.

### D. `isBonus=false` Calls (Existing Paths)

When `isBonus=false`, the function takes the `else` branch: `r = randWord` (DUP1, ~3 gas). The old single-argument function had the same `r = randWord` assignment implicitly. The only new cost is the JUMPI for the conditional (~10 gas per call).

There are 3 `isBonus=false` calls in the worst case (L336, L585, L1158). Total overhead: **30 gas** (already included in section A).

---

## 2. Gas Removals (Phase 218 Eliminated Costs)

### A. `_syncDailyWinningTraits` Removal (SSTORE)

The old `_syncDailyWinningTraits` function performed:
| Operation | Opcode | Gas (worst case) |
|-----------|--------|-------------------|
| Read `dailyJackpotTraitsPacked` | SLOAD (warm, same-tx) | 100 |
| Mask + shift for traits field | AND, SHL, OR (x3 fields: traits, level, day) | ~30 |
| Write packed value | SSTORE (warm dirty slot) | 100 |
| Function call overhead | JUMP + JUMPDEST + stack ops | ~30 |
| **Per-call total** | | **~260** |

Call sites removed:
| Location | Context | Calls removed |
|----------|---------|---------------|
| `payDailyJackpot` jackpot path | After trait roll | 1 |
| `payDailyJackpot` purchase path | After trait roll | 1 |

Only 1 call per drawing (paths are mutually exclusive).

**SSTORE removal savings: 260 gas per drawing.**

### B. `_loadDailyWinningTraits` Removal (SLOAD)

The old `_loadDailyWinningTraits` function performed:
| Operation | Opcode | Gas (worst case) |
|-----------|--------|-------------------|
| Read `dailyJackpotTraitsPacked` | SLOAD (warm) | 100 |
| Unpack day field | SHR + AND | ~10 |
| Day validation check | comparison + JUMPI | ~13 |
| Unpack traits field | AND | ~5 |
| Function call overhead | JUMP + JUMPDEST + stack ops | ~30 |
| **Per-call total** | | **~158** |

Call sites removed:
| Location | Context | Calls removed |
|----------|---------|---------------|
| `_resumeDailyEth` (old code) | Read stored traits for ETH distribution call 2 | 1 |
| `payDailyJackpotCoinAndTickets` (old code) | Read stored traits for coin+ticket distribution | 1 |

In the worst case (two-call daily ETH split active), both calls execute in the same transaction. The SLOAD at the second call is warm (100 gas) since the first call already touched the slot.

**SLOAD removal savings: 316 gas** (158 * 2 calls per worst case).

### C. `_selectDailyCoinTargetLevel` Function Removal

The old function did:
| Operation | Gas |
|-----------|-----|
| `lvl + 1 + uint24(entropy % 4)` inline math | ~14 |
| Function call overhead (JUMP/JUMPDEST/stack) | ~30 |
| **Per-call total** | **~44** |

This was replaced by inline math at the caller sites or caller-provided min/max parameters. The inline math costs ~14 gas. Net savings per call: ~30 gas (function overhead only).

Call sites: 2 (payDailyJackpotCoinAndTickets, payDailyCoinJackpot).

**Function removal savings: 60 gas** (30 * 2).

### D. DJT Storage Slot Constants Removal

The removed constants (`DJT_TRAITS_SHIFT`, `DJT_TRAITS_MASK`, etc.) were `internal constant` values embedded in bytecode. Their removal reduces contract size but has zero runtime gas impact (constants are inlined by the compiler as PUSH instructions).

**Constant removal savings: 0 gas** (deployment size only).

---

## 3. Net Delta Calculation

### Per-Drawing Gas Delta

| Category | Gas Change | Notes |
|----------|-----------|-------|
| **Additions** | | |
| keccak256 bonus derivation (3 calls) | +183 | 3 * 61 gas per `isBonus=true` call |
| JUMPI overhead on `isBonus=false` calls (3 calls) | +30 | 3 * 10 gas per conditional |
| DailyWinningTraits LOG2 emission | +1,917 | 1 event per drawing |
| Event supporting computation | +29 | XOR, SHL, MOD, ADD for target level |
| **Subtotal additions** | **+2,159** | |
| **Removals** | | |
| `_syncDailyWinningTraits` SSTORE | -260 | 1 call removed per drawing |
| `_loadDailyWinningTraits` SLOAD (2 calls) | -316 | 2 calls removed (resumeEth + coinTickets) |
| `_selectDailyCoinTargetLevel` overhead (2 calls) | -60 | Function call overhead eliminated |
| **Subtotal removals** | **-636** | |
| | | |
| **NET DELTA: +1,523 gas per drawing** | | |

### Per-creditFlip Gas Delta

The bonus derivation happens ONCE per drawing in the jackpot function, not once per creditFlip. The `_awardDailyCoinToTraitWinners` function receives already-derived `bonusTraitsPacked` as a parameter and loops over up to 50 winners calling `creditFlip` on each. None of the Phase 218 changes affect the per-creditFlip loop body.

**Per-creditFlip overhead from Phase 218: ZERO.**

The 50 creditFlip calls (DAILY_COIN_MAX_WINNERS = 50) are identical to before Phase 218 in per-iteration gas cost.

### Worst-Case Total (50 creditFlip in single jackpot transition, per D-06)

The worst case is the jackpot-phase daily with two-call ETH split, coin distribution with 50 creditFlip calls, and ticket distribution. Phase 218 adds a fixed +1,523 gas to this entire transaction regardless of creditFlip count.

---

## 4. Headroom Verification

| Metric | Value |
|--------|-------|
| Previous worst case | 7,023,530 gas |
| Phase 218 net delta | +1,523 gas |
| **New worst case** | **7,025,053 gas** |
| Block gas limit | 14,000,000 gas |
| **New headroom** | **14,000,000 / 7,025,053 = 1.993x** |
| Previous headroom | 1.993x |
| Headroom reduction | 0.0004x (negligible) |

The headroom calculation:
- 14,000,000 / 7,023,530 = 1.99330... (before Phase 218)
- 14,000,000 / 7,025,053 = 1.99287... (after Phase 218)
- Delta: 0.00043x

**VERDICT: 1.99x headroom margin PRESERVED.**

The net gas delta of +1,523 gas per drawing is 0.022% of the baseline worst case. The headroom ratio rounds to the same 1.99x at two decimal places. Even with conservative rounding, the margin stays above 1.99x.

The per-creditFlip gas is unchanged because bonus derivation is a per-drawing fixed cost, not a per-winner cost. The 50-creditFlip worst case adds zero Phase-218 overhead beyond the fixed 1,523 gas already accounted for.

---

## Methodology Notes

- All gas costs from EVM Yellow Paper Appendix G opcode table
- SLOAD warm access: 100 gas (EIP-2929 -- all slots accessed within same transaction context)
- SSTORE warm dirty: 100 gas (EIP-2200 -- slot already written in same transaction)
- SHA3 (keccak256): 30 base + 6 per 32-byte word (Yellow Paper)
- LOG2: 375 base + 375 per topic (Yellow Paper); data cost 8 gas per byte
- Function call overhead: ~30 gas (JUMP + JUMPDEST + stack operations)
- No Foundry benchmarks used -- derivation is purely mathematical from opcode costs
- Conservative assumptions: warm access costs used (lower savings) since DJT slot was typically accessed multiple times per transaction

---

*Derived: 2026-04-12*
*Phase: 219-delta-audit-gas-verification, Plan 02*
