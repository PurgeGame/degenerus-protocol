# Unit 3: Jackpot Distribution -- Skeptic Review

**Reviewer:** Skeptic Agent (Senior Solidity Security Researcher)
**Contracts:** DegenerusGameJackpotModule.sol (2,715 lines), DegenerusGamePayoutUtils.sol (92 lines)
**Date:** 2026-03-25
**Methodology:** Independent code verification per ULTIMATE-AUDIT-DESIGN.md Agent 2 mandate. Every finding traced against actual source. All BAF-critical chains independently verified. Inline assembly independently verified. Checklist completeness independently verified.

---

## Review Summary

| ID | Finding Title | Mad Genius | Skeptic | Severity | Notes |
|----|-------------|------------|---------|----------|-------|
| F-01 | Yield surplus `obligations` snapshot includes stale claimablePool after _addClaimableEth writes | INVESTIGATE | DOWNGRADE TO INFO (with correction) | INFO | Mad Genius claimed auto-rebuy unreachable for VAULT/SDGNRS -- partially incorrect. VAULT can enable auto-rebuy via DegenerusVault.gameSetAutoRebuy. Stale snapshot still non-exploitable. |
| F-02 | Assembly uses `add(levelSlot, traitId)` for inner mapping -- correct but non-obvious | INVESTIGATE | DOWNGRADE TO INFO | INFO | Verified correct for Solidity fixed-array layout. Non-upgradeable contract eliminates future risk. |
| F-03 | `processed` counter approximation via `writesUsed >> 1` may cause LCG seed drift on resume | INVESTIGATE | DOWNGRADE TO INFO | INFO | Confirmed INFO. Trait distribution remains deterministic and VRF-derived. No economic impact. |
| F-04 | Double `_getFuturePrizePool()` read in earlybird deduction | INVESTIGATE | DOWNGRADE TO INFO | INFO | Confirmed: two warm SLOADs (200 gas) with no intervening writes. Gas inefficiency only. |
| F-05 | `calc.reserved` can be 0 when takeProfit is 0 -- dust dropped | INVESTIGATE | DOWNGRADE TO INFO | INFO | Confirmed: dust < ticketPrice/4 is dropped by design (NatSpec explicit). No accounting drift. |

**Final count:** 0 CONFIRMED exploitable, 0 FALSE POSITIVE, 5 DOWNGRADE TO INFO

---

## Detailed Finding Reviews

### F-01: Yield Surplus Obligations Snapshot Staleness

**Mad Genius Verdict:** INVESTIGATE (INFO)
**Skeptic Verdict:** DOWNGRADE TO INFO (with factual correction)

**Analysis:**

The Mad Genius correctly identified that `_distributeYieldSurplus` (C2, L883-914) computes an `obligations` snapshot at L886-890 that includes `currentPrizePool + _getNextPrizePool() + claimablePool + _getFuturePrizePool() + yieldAccumulator`, then uses it as a one-time surplus gate at L892 (`if (totalBal <= obligations) return`). After the gate passes, `_addClaimableEth(VAULT, ...)` at L901 and `_addClaimableEth(SDGNRS, ...)` at L906 may trigger C4 `_processAutoRebuy`, which would write to `futurePrizePool` or `nextPrizePool`, making the snapshot stale.

**Factual correction to Mad Genius analysis:** The Mad Genius stated: "VAULT and SDGNRS are contract addresses that almost certainly do NOT have autoRebuy enabled -- they have no UI/transaction path to enable auto-rebuy."

This is **partially incorrect**. I independently verified:

- **VAULT (DegenerusVault):** Has `gameSetAutoRebuy(bool enabled)` at DegenerusVault.sol L643, which calls `gamePlayer.setAutoRebuy(address(this), enabled)`. The vault owner (>50.1% DGVE holder) CAN enable auto-rebuy for the vault address. **Auto-rebuy IS reachable for VAULT.**
- **SDGNRS (StakedDegenerusStonk):** Has NO `setAutoRebuy` function or equivalent. `grep` across the entire contract confirms zero references. **Auto-rebuy IS unreachable for SDGNRS.** The Mad Genius is correct for SDGNRS but wrong for VAULT.

**Impact analysis even with VAULT auto-rebuy enabled:**

If VAULT has auto-rebuy enabled and the `_addClaimableEth(VAULT, stakeholderShare, rngWord)` call at L901 triggers C4:
1. C4 would divert part of `stakeholderShare` into `futurePrizePool` or `nextPrizePool` (via `_setFuturePrizePool` L982 or `_setNextPrizePool` L984)
2. The `obligations` snapshot at L886-890 would now understate actual obligations (since pool balances increased)
3. However, `obligations` is ONLY used at L892 for the surplus gate check. It is NOT used for computing `stakeholderShare` or `accumulatorShare` (those derive from `yieldPool = totalBal - obligations` at L894, which is computed once)
4. The stale snapshot would make `yieldPool` appear slightly larger than it should be. But the surplus calculation already leaves an ~8% buffer unextracted (NatSpec at L896: "~8% buffer left unextracted"). The auto-rebuy diversion would move ETH within the protocol's pool system, not extract it -- so the total balance `totalBal` doesn't change
5. The second call `_addClaimableEth(SDGNRS, stakeholderShare, ...)` at L906 would NOT trigger auto-rebuy (SDGNRS cannot enable it), so only VAULT's share could diverge

**Why this is still INFO, not exploitable:**
- The `obligations` understatement is directionally conservative: if auto-rebuy increased pool values, actual obligations are HIGHER, meaning the real surplus is SMALLER. The protocol distributes based on a slightly-too-large surplus. The excess distribution is bounded by `stakeholderShare * (1 - reserved/weiAmount)` which is the auto-rebuy diversion fraction. Given the 8% buffer already left unextracted, this is absorbed.
- No external attacker can trigger this -- it requires the vault owner to enable auto-rebuy AND yield surplus to exist simultaneously.
- The ETH stays within the protocol's pool system (moved to futurePrizePool/nextPrizePool).

**If DOWNGRADE TO INFO:**
- Original concern: Stale obligations snapshot after _addClaimableEth writes could cause incorrect surplus distribution
- Why downgrade: The snapshot is only used as a one-time gate (L892), never written back. The directional error is conservative (overestimates surplus by at most the auto-rebuy diversion, absorbed by 8% buffer). No external attack surface. ETH remains within protocol pools.

---

### F-02: Assembly Storage Slot Calculation Non-obvious

**Mad Genius Verdict:** INVESTIGATE (INFO)
**Skeptic Verdict:** DOWNGRADE TO INFO

**Analysis:**

I independently verified the assembly in `_raritySymbolBatch` (C20, L2050-2145):

1. **Level slot computation (L2110-2113):**
   ```solidity
   mstore(0x00, lvl)
   mstore(0x20, traitBurnTicket.slot)
   levelSlot := keccak256(0x00, 0x40)
   ```
   This computes `keccak256(abi.encode(lvl, traitBurnTicket.slot))`. For `mapping(uint24 => address[][256])`, the Solidity standard layout hashes the key with the mapping slot to get the base slot for the 256-element fixed array. **CORRECT.**

2. **Per-trait slot (L2123):** `let elem := add(levelSlot, traitId)`. For a fixed-size array `address[][256]`, element at index `traitId` is at slot `levelSlot + traitId`. This is standard Solidity fixed-array layout within mappings. `traitId` is [0,255], so all 256 elements occupy consecutive slots. **CORRECT.**

3. **Array length (L2124-2126):** `sload(elem)` reads the dynamic array length. `sstore(elem, newLen)` updates it. **CORRECT.**

4. **Data slot (L2129-2130):** `keccak256(abi.encode(elem))` gives the data start for the dynamic `address[]`. **CORRECT.**

5. **Write position (L2131):** `add(data, len)` gives the next available slot (each address uses one full slot). **CORRECT.**

**If DOWNGRADE TO INFO:**
- Original concern: `add(levelSlot, traitId)` assumes fixed-array layout, which could break if declaration changed
- Why downgrade: The code is correct for `mapping(uint24 => address[][256])`. The contract is non-upgradeable (immutable deployment). The assembly block has explicit NatSpec comments documenting the layout assumption (L2104-2108). No practical risk.

---

### F-03: Processed Counter Approximation in processTicketBatch

**Mad Genius Verdict:** INVESTIGATE (INFO)
**Skeptic Verdict:** DOWNGRADE TO INFO

**Analysis:**

I verified `processTicketBatch` (B6, L1812-1873). The `processed` counter at the loop accumulation point uses `writesUsed >> 1` as an approximation of tickets processed within a single ticket entry. This value feeds into `_generateTicketBatch` as the `startIndex`, which affects the LCG seed derivation in `_raritySymbolBatch` (L2074: `seed = (baseKey + groupIdx) ^ entropyWord` where `groupIdx = i >> 4` and `i` includes `startIndex`).

**Verification of impact:**
- If `processed` is off by a few units, the LCG seed for subsequent groups changes, producing different trait assignments
- The traits are still: (a) deterministic given VRF seed + queue position, (b) VRF-derived (not player-controllable), (c) uniformly distributed per the LCG's full-period guarantee
- Trait assignment affects which quadrant/color a ticket gets, not its economic value
- The approximation only matters on resume (when a batch is split across multiple advanceGame calls within the same entry). For complete single-pass entries, `processed` is not used

**If DOWNGRADE TO INFO:**
- Original concern: Resume-within-entry produces slightly different traits than single-pass
- Why downgrade: Trait aesthetics only, no economic impact. Distribution remains deterministic and VRF-derived. The approximation is a gas optimization trade-off (exact tracking would require an additional SSTORE per loop iteration).

---

### F-04: Double _getFuturePrizePool() Read

**Mad Genius Verdict:** INVESTIGATE (INFO)
**Skeptic Verdict:** DOWNGRADE TO INFO

**Analysis:**

I verified the cited locations:
- L774: `uint256 futurePool = _getFuturePrizePool();` (read for calculation)
- L778: `_setFuturePrizePool(_getFuturePrizePool() - reserveContribution);` (read for deduction)

Both calls resolve to `_getPrizePools()` which reads `prizePoolsPacked` from storage. No writes occur between L774 and L778. The second SLOAD is warm (100 gas, EIP-2929). Same pattern at L601/L604 in the early-burn path.

**If DOWNGRADE TO INFO:**
- Original concern: Double SLOAD reads the same value
- Why downgrade: Pure gas inefficiency (100 gas per occurrence). No correctness impact. Could be optimized by reusing the L774 value, but savings are trivial relative to function gas cost.

---

### F-05: Zero takeProfit Drops Dust

**Mad Genius Verdict:** INVESTIGATE (INFO)
**Skeptic Verdict:** DOWNGRADE TO INFO

**Analysis:**

I verified `_processAutoRebuy` (C4, L959-999) and `_calcAutoRebuy` (D16, PayoutUtils L38-72):

When `state.takeProfit == 0`:
- `calc.reserved = 0` (PayoutUtils L50: no division by zero -- the `if (state.takeProfit != 0)` guard at L49 skips the assignment)
- `calc.rebuyAmount = weiAmount - 0 = weiAmount` (L52)
- `calc.ethSpent = baseTickets * ticketPrice` (L67) where `baseTickets = rebuyAmount / ticketPrice`
- Dust = `rebuyAmount - ethSpent` = `weiAmount % (ticketPrice / 4)` -- this is the integer division remainder
- The dust is not credited to player, not added to any pool

**Dust bound:** `ticketPrice = PriceLookupLib.priceForLevel(targetLevel) >> 2`. For level 1, this is approximately 0.009 ETH / 4 = 0.00225 ETH. Dust is always < this value.

**NatSpec confirmation:** L954: "Fractional dust is dropped unconditionally." This is explicitly documented as intentional behavior.

**If DOWNGRADE TO INFO:**
- Original concern: Entire winnings converted to tickets with no claimable credit when takeProfit is 0
- Why downgrade: Dust is bounded by ticketPrice/4 (sub-cent at most levels), explicitly documented as intentional. No accounting drift because the ETH is fully accounted: `ethSpent` goes to pools, `reserved` (0) goes to claimable, dust is the sub-ticketPrice remainder.

---

## BAF-Critical Path Independent Verification

### Chain 1: B2 -> C11 -> C3 -> C4 (payDailyJackpot Phase 0 -> _processDailyEth -> _addClaimableEth -> _processAutoRebuy)

**Mad Genius verdict:** SAFE
**Skeptic independent analysis:**

I read B2 (L313-637), C11 (L1338-1433), C3 (L928-949), C4 (L959-999).

- **Parent B2 caches:** `poolSnapshot = currentPrizePool` at L353. Used ONLY at L364 for `budget = (poolSnapshot * dailyBps) / 10_000`. NOT used after L364. NOT written back. The `currentPrizePool -= paidDailyEth` at L503 is a fresh storage read-modify-write (confirmed: `currentPrizePool` is a storage variable, Solidity generates SLOAD for the read side of `-=`).
- **Parent C11 caches:** `liabilityDelta` (running sum of C3 return values, L1365), `paidEth` (running sum of perWinner, L1419). Neither is a prize pool value. C11 does NOT read `futurePrizePool`, `nextPrizePool`, or `currentPrizePool` into any local variable.
- **C4 writes:** `_setFuturePrizePool(_getFuturePrizePool() + calc.ethSpent)` at L982 or `_setNextPrizePool(_getNextPrizePool() + calc.ethSpent)` at L984. Both use fresh reads via `_getFuturePrizePool()` / `_getNextPrizePool()`.
- **Does any cached local get overwritten after C4 returns?** No. `poolSnapshot` is stale but never used again after L364. `liabilityDelta` and `paidEth` are return-value accumulators, not pool caches.

**Skeptic verdict:** AGREES WITH MAD GENIUS -- SAFE

### Chain 2: B2 -> C11 -> C3 -> C4 (payDailyJackpot Phase 1 carryover)

**Mad Genius verdict:** SAFE
**Skeptic independent analysis:**

- **Parent B2 caches:** `carryPool = dailyCarryoverEthPool` at L536. This is the daily carryover budget, NOT a prize pool value (currentPrizePool / futurePrizePool / nextPrizePool).
- Same C11 analysis as Chain 1 -- no pool caches.

**Skeptic verdict:** AGREES WITH MAD GENIUS -- SAFE

### Chain 3: B2 -> C9 -> C10 -> C12 -> C13 -> C14 -> C3 -> C4 (early-burn path)

**Mad Genius verdict:** SAFE
**Skeptic independent analysis:**

- **Parent B2 early-burn:** `ethDaySlice` computed at L601, deducted from futurePrizePool at L604 BEFORE calling `_executeJackpot` at L617. `ethPool = ethDaySlice` at L607 is a local value derived from the deduction, not a storage cache.
- **C9 (L1280-1294):** Unpacks JackpotParams struct. `jp.ethPool` is a memory value, not a storage cache.
- **C10 (L1297-1322):** Passes parameters to C12. No pool caches.
- **C12 (L1435-1474):** `JackpotEthCtx memory ctx` contains `entropyState`, `liabilityDelta`, `totalPaidEth`, `lvl` -- NONE are pool values. `claimablePool += ctx.liabilityDelta` at L1471 is a fresh storage read-modify-write.
- **C13 (L1477-1504):** Passes ctx by reference. Returns results into ctx fields.
- **C14 (L1528-1655):** `totalPayout`, `totalLiability`, `totalWhalePassSpent` are running sums. NOT pool caches.

**Skeptic verdict:** AGREES WITH MAD GENIUS -- SAFE

### Chain 4: B1 -> C12 -> C13 -> C14 -> C3 -> C4 (runTerminalJackpot)

**Mad Genius verdict:** SAFE
**Skeptic independent analysis:**

- **B1 (L272-308):** `poolWei` is a parameter, not a storage read. `paidWei` is the return value. No storage caches of any kind.
- Same C12/C13/C14 analysis as Chain 3.

**Skeptic verdict:** AGREES WITH MAD GENIUS -- SAFE

### Chain 5: B5 -> C2 -> C3 -> C4 (consolidatePrizePools -> _distributeYieldSurplus)

**Mad Genius verdict:** SAFE (with F-01 INFO)
**Skeptic independent analysis:**

- **Parent B5 (L850-879):** All prize pool writes at L855 (`_setFuturePrizePool`), L856 (`yieldAccumulator`), L860 (`currentPrizePool +=`), L861 (`_setNextPrizePool(0)`), L870 (`_setFuturePrizePool(keepWei)`), L871 (`currentPrizePool +=`) execute BEFORE `_distributeYieldSurplus` is called at L878. B5 does NOT hold any pool value in a local variable across the L878 call boundary.
- **C2 (L883-914):** `obligations` snapshot at L886-890 is used ONLY for the surplus gate at L892. Not written back. After the gate, `stakeholderShare` and `accumulatorShare` are derived from `yieldPool` (computed once at L894). `claimablePool += claimableDelta` at L911 and `yieldAccumulator += accumulatorShare` at L913 are fresh storage read-modify-writes.
- **Correction (F-01):** VAULT can enable auto-rebuy. If it does, C4 writes to futurePrizePool/nextPrizePool would make `obligations` stale. But `obligations` is never reused after L892. The stale value is directionally conservative.

**Skeptic verdict:** AGREES WITH MAD GENIUS -- SAFE (with F-01 INFO correction noted above)

### Chain 6: B2 -> C1 (earlybird lootbox -- does NOT reach _addClaimableEth)

**Mad Genius verdict:** No BAF chain (C1 does not call _addClaimableEth)
**Skeptic independent analysis:**

Verified: C1 `_runEarlyBirdLootboxJackpot` (L772-835) calls `_setFuturePrizePool` (L778), `_queueTickets` (L819), `_setNextPrizePool` (L834). No call to `_addClaimableEth`. **Confirmed: not a BAF chain.**

**Skeptic verdict:** AGREES WITH MAD GENIUS -- not applicable

---

## Inline Assembly Independent Verification

### _raritySymbolBatch (C20, L2050-2145)

**1. Expected Solidity storage slot for `traitBurnTicket[lvl][traitId]`:**

`traitBurnTicket` is declared as `mapping(uint24 => address[][256])` in DegenerusGameStorage.

Standard Solidity layout:
- Step 1: `keccak256(abi.encode(lvl, traitBurnTicket.slot))` gives the base slot for the 256-element fixed array at level `lvl`
- Step 2: For fixed array element `traitId`, slot = `base + traitId` (consecutive slots for fixed arrays)
- Step 3: Each `address[]` is a dynamic array. Length at slot `base + traitId`. Data starts at `keccak256(abi.encode(base + traitId))`.

**2. Assembly computation comparison:**

```solidity
// L2110-2113
mstore(0x00, lvl)
mstore(0x20, traitBurnTicket.slot)
levelSlot := keccak256(0x00, 0x40)
```
This is `keccak256(abi.encode(lvl, slot))`. **MATCHES Step 1.**

```solidity
// L2123
let elem := add(levelSlot, traitId)
```
**MATCHES Step 2.** Fixed-array index = base + index.

```solidity
// L2124
let len := sload(elem)
```
Reads dynamic array length from the element's slot. **MATCHES Step 3 (length).**

```solidity
// L2129-2130
mstore(0x00, elem)
let data := keccak256(0x00, 0x20)
```
This is `keccak256(abi.encode(elem))`. **MATCHES Step 3 (data start).**

```solidity
// L2131
let dst := add(data, len)
```
Next write position = data start + current length. Each address occupies one full 32-byte slot. **CORRECT.**

**3. Array length and data slot arithmetic:**

- `newLen = add(len, occurrences)` at L2125: correct addition of new entries
- `sstore(elem, newLen)` at L2126: writes updated length back
- Loop at L2132-2139: writes `player` address to consecutive slots starting at `dst`
- Each iteration advances `dst` by 1 (one slot per address): **CORRECT**

**4. Memory safety:** Only scratch space (0x00-0x3F) used for `mstore`. No interference with Solidity-managed memory. The `"memory-safe"` annotation is valid.

**Skeptic verdict:** AGREES WITH MAD GENIUS -- assembly is CORRECT. Storage slot computation matches Solidity standard layout. Array accounting is correct. No collision risk. Memory safety verified.

---

## Checklist Completeness Verification (VAL-04)

### Methodology

1. Ran `grep -n "function "` across both DegenerusGameJackpotModule.sol and DegenerusGamePayoutUtils.sol
2. Counted all function declarations
3. Cross-referenced every function against COVERAGE-CHECKLIST.md entries
4. Verified categorization (B/C/D) by checking each function's visibility modifier and whether it writes to storage

### Functions Found

**DegenerusGameJackpotModule.sol:** 52 functions
**DegenerusGamePayoutUtils.sol:** 3 functions
**Total:** 55 functions

### Functions Found Not on Checklist

None. All 55 functions appear in the COVERAGE-CHECKLIST.md:
- 7 in Category B (external state-changing)
- 28 in Category C (internal/private state-changing)
- 20 in Category D (view/pure)

### Miscategorized Functions

None. I verified:
- All 7 Category B functions are `external` and write to storage: CORRECT
- All 28 Category C functions are `private` or `internal` and write to storage (or call functions that do): CORRECT
- All 20 Category D functions are `view` or `pure` with zero storage writes: CORRECT

Specific reclassification verification (the 7 functions moved from C to D):
1. `_calcAutoRebuy` (PayoutUtils L38-72): declared `internal pure` -- CORRECT as D16
2. `_validateTicketBudget` (L1024-1031): declared `private view`, reads storage but writes nothing -- CORRECT as D17
3. `_packDailyTicketBudgets` (L2676-2687): declared `private pure` -- CORRECT as D18
4. `_unpackDailyTicketBudgets` (L2689-2705): declared `private pure` -- CORRECT as D19
5. `_selectCarryoverSourceOffset` (L2631-2674): declared `private view` -- CORRECT as D20
6. `_highestCarryoverSourceOffset` (L2613-2626): declared `private view` -- CORRECT as D21
7. `_rollRemainder` (L2024-2031): declared `private pure` -- CORRECT as D22

### Verdict: COMPLETE

The checklist contains every function declared in both contracts. All categorizations are correct. No state-changing functions are miscategorized as view/pure. No functions are missing.

---

## Overall Assessment

- **Total findings reviewed:** 5
- **Confirmed exploitable:** 0
- **False Positives:** 0
- **Downgrades to INFO:** 5 (F-01 through F-05)
- **BAF-critical verdicts:** AGREES with Mad Genius on all 6 chains (all SAFE)
- **Assembly verdicts:** AGREES with Mad Genius (CORRECT -- storage slot computation matches Solidity standard layout)
- **Checklist completeness:** COMPLETE (55/55 functions, all correctly categorized)

### Correction to Mad Genius Analysis

F-01: The Mad Genius's claim that "auto-rebuy is unreachable for VAULT and SDGNRS contract addresses" is **partially incorrect**. DegenerusVault.sol has `gameSetAutoRebuy(bool enabled)` at L643 which allows the vault owner to enable auto-rebuy for the vault address. StakedDegenerusStonk has no such function, so the claim holds for SDGNRS. This correction does not change the finding severity (still INFO) because the stale `obligations` snapshot is only used as a one-time gate and the directional error is conservative. However, the attack report should note this factual correction for completeness.

### Unit 3 Security Posture

DegenerusGameJackpotModule.sol and DegenerusGamePayoutUtils.sol demonstrate correct BAF-pattern handling across all 6 traced call chains. The key design patterns that prevent cache-overwrite bugs:
1. **Fresh reads for pool writes:** Every `_setFuturePrizePool` / `_setNextPrizePool` call uses a fresh `_getFuturePrizePool()` / `_getNextPrizePool()` read
2. **Return value tracking:** All `_addClaimableEth` callers use the return value (`claimableDelta`) for liability tracking, not the original `weiAmount`
3. **No stale writebacks:** `poolSnapshot` (B2 L353) is used read-only for budget calculation and never written back
4. **Aggregate-at-end pattern:** `claimablePool` updates happen after loops complete, using accumulated return values

No CRITICAL, HIGH, MEDIUM, or LOW findings. 5 INFO-level observations, none exploitable.
