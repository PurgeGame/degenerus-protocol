# Unit 3: Jackpot Distribution -- Final Findings

## Audit Scope

- **Contracts:** DegenerusGameJackpotModule.sol (2,715 lines), DegenerusGamePayoutUtils.sol (92 lines)
- **Audit type:** Three-agent adversarial (Taskmaster + Mad Genius + Skeptic)
- **Coverage verdict:** PASS (Taskmaster -- 100% coverage, 0 gaps)
- **Functions analyzed:**
  - External state-changing (B): 7/7 (full analysis per D-02)
  - Internal state-changing helpers (C): 28/28 (via caller call trees; standalone for [MULTI-PARENT] per D-03)
  - View/Pure (D): 20/20 (minimal review; RNG derivation and assembly get extra scrutiny)
  - **Total: 55/55**
- **BAF-critical verification:** SAFE -- all 6 chains verified by both Mad Genius and Skeptic independently
- **Inline assembly verification:** CORRECT -- _raritySymbolBatch storage slot computation verified by both agents

## Findings Summary

| Severity | Count |
|----------|-------|
| CRITICAL | 0 |
| HIGH | 0 |
| MEDIUM | 0 |
| LOW | 0 |
| INFO | 5 |
| **Total** | **5** |

## Confirmed Findings

No vulnerabilities or issues were identified in Unit 3. All 5 Mad Genius findings were reviewed by the Skeptic and downgraded to INFO. None are exploitable. They are documented below for transparency and completeness.

### [INFO] F-01: Yield Surplus Obligations Snapshot Staleness

**Location:** `DegenerusGameJackpotModule.sol` lines 883-914, function `_distributeYieldSurplus()` (C2)
**Found by:** Mad Genius (Attack Report)
**Reviewed by:** Skeptic (Review -- with factual correction)
**Severity:** INFO -- stale snapshot is directionally conservative, absorbed by 8% buffer, no external attack surface

**Description:**
`_distributeYieldSurplus` computes an `obligations` snapshot at L886-890 that includes `currentPrizePool + _getNextPrizePool() + claimablePool + _getFuturePrizePool() + yieldAccumulator`. After the surplus gate check at L892, `_addClaimableEth(VAULT, ...)` at L901 may trigger `_processAutoRebuy` (C4), which writes to `futurePrizePool` or `nextPrizePool`, making the `obligations` snapshot stale.

**Skeptic Correction:** The Mad Genius stated auto-rebuy is unreachable for both VAULT and SDGNRS contract addresses. This is **partially incorrect**:
- **VAULT (DegenerusVault):** CAN enable auto-rebuy via `gameSetAutoRebuy(bool enabled)` at DegenerusVault.sol L643. Auto-rebuy IS reachable for VAULT.
- **SDGNRS (StakedDegenerusStonk):** Has NO `setAutoRebuy` function. Auto-rebuy IS unreachable for SDGNRS. The Mad Genius is correct for SDGNRS only.

**Why INFO (not exploitable):**
- The `obligations` snapshot is ONLY used at L892 for the surplus gate check. It is NOT used for computing `stakeholderShare` or `accumulatorShare`.
- The staleness direction is conservative: if auto-rebuy increased pool values, actual obligations are HIGHER, meaning the real surplus is SMALLER. The protocol distributes based on a slightly-too-large surplus.
- The 8% buffer left unextracted (NatSpec L896) absorbs the difference.
- No external attacker can trigger this -- requires the vault owner to enable auto-rebuy AND yield surplus to exist simultaneously.
- ETH stays within the protocol's pool system (moved to futurePrizePool/nextPrizePool).

**Evidence:**
- Mad Genius analysis: ATTACK-REPORT.md -- B5 consolidatePrizePools section, C2 _distributeYieldSurplus analysis
- Skeptic verification: SKEPTIC-REVIEW.md -- F-01 detailed review with factual correction

---

### [INFO] F-02: Assembly Storage Slot Calculation Non-obvious

**Location:** `DegenerusGameJackpotModule.sol` lines 2050-2145, function `_raritySymbolBatch()` (C20)
**Found by:** Mad Genius (Attack Report)
**Reviewed by:** Skeptic (Review)
**Severity:** INFO -- assembly is correct for current storage layout, contract is non-upgradeable

**Description:**
The inline Yul assembly in `_raritySymbolBatch` uses `add(levelSlot, traitId)` at L2123 for the inner mapping access within `mapping(uint24 => address[][256])`. This relies on the Solidity fixed-array-within-mapping layout assumption: for a fixed-size array `address[][256]`, element at index `traitId` occupies slot `base + traitId`.

**Why INFO:**
- The code is CORRECT for the declared type `mapping(uint24 => address[][256])`.
- The contract is non-upgradeable (immutable deployment), so the storage layout cannot change.
- NatSpec comments at L2104-2108 document the layout assumption.
- Both agents independently verified the slot computation matches Solidity standard layout.

**Evidence:**
- Mad Genius analysis: ATTACK-REPORT.md -- C20 _raritySymbolBatch inline assembly section
- Skeptic verification: SKEPTIC-REVIEW.md -- Inline Assembly Independent Verification section

---

### [INFO] F-03: Processed Counter Approximation in processTicketBatch

**Location:** `DegenerusGameJackpotModule.sol` lines 1812-1873, function `processTicketBatch()` (B6)
**Found by:** Mad Genius (Attack Report)
**Reviewed by:** Skeptic (Review)
**Severity:** INFO -- trait aesthetics only, no economic impact

**Description:**
The `processed` counter uses `writesUsed >> 1` as an approximation of tickets processed within a single ticket entry. This value feeds into `_generateTicketBatch` as `startIndex`, which affects the LCG seed derivation in `_raritySymbolBatch` (L2074). If a batch is split across multiple `advanceGame` calls within the same entry, resume may produce slightly different trait assignments than a single-pass execution would.

**Why INFO:**
- Traits are (a) deterministic given VRF seed + queue position, (b) VRF-derived (not player-controllable), (c) uniformly distributed per the LCG's full-period guarantee.
- Trait assignment affects which quadrant/color a ticket gets, not its economic value.
- The approximation only matters on resume (split across calls). Single-pass entries are unaffected.
- Exact tracking would require an additional SSTORE per loop iteration (gas cost not justified).

**Evidence:**
- Mad Genius analysis: ATTACK-REPORT.md -- B6 processTicketBatch section
- Skeptic verification: SKEPTIC-REVIEW.md -- F-03 detailed review

---

### [INFO] F-04: Double _getFuturePrizePool() Read in Earlybird Deduction

**Location:** `DegenerusGameJackpotModule.sol` lines 774-778, function `_runEarlyBirdLootboxJackpot()` (C1)
**Found by:** Mad Genius (Attack Report)
**Reviewed by:** Skeptic (Review)
**Severity:** INFO -- pure gas inefficiency (100 gas), no correctness impact

**Description:**
At L774 `futurePool = _getFuturePrizePool()` reads the prize pool for calculation. At L778 `_setFuturePrizePool(_getFuturePrizePool() - reserveContribution)` reads the same value again via a second SLOAD. No writes occur between L774 and L778, so both reads return the same value. Same pattern at L601/L604 in the early-burn path.

**Why INFO:**
- The second SLOAD is warm (100 gas, EIP-2929). No correctness impact.
- Could be optimized by reusing the L774 value, but savings are trivial relative to function gas cost.

**Evidence:**
- Mad Genius analysis: ATTACK-REPORT.md -- B2 payDailyJackpot section
- Skeptic verification: SKEPTIC-REVIEW.md -- F-04 detailed review

---

### [INFO] F-05: Zero takeProfit Drops Dust in Auto-Rebuy

**Location:** `DegenerusGameJackpotModule.sol` lines 959-999, function `_processAutoRebuy()` (C4); `DegenerusGamePayoutUtils.sol` lines 38-72, function `_calcAutoRebuy()` (D16)
**Found by:** Mad Genius (Attack Report)
**Reviewed by:** Skeptic (Review)
**Severity:** INFO -- dust bounded by ticketPrice/4, explicitly documented as intentional

**Description:**
When `state.takeProfit == 0`, `calc.reserved = 0` and the entire `weiAmount` is converted to tickets. The integer division remainder (`weiAmount % (ticketPrice / 4)`) is dropped -- not credited to the player and not added to any pool.

**Why INFO:**
- Dust is always less than `ticketPrice / 4` (approximately 0.00225 ETH at level 1, sub-cent at most levels).
- NatSpec at L954 explicitly documents: "Fractional dust is dropped unconditionally."
- No accounting drift: `ethSpent` goes to pools, `reserved` (0) goes to claimable, dust is the sub-ticketPrice remainder. All ETH is fully accounted.

**Evidence:**
- Mad Genius analysis: ATTACK-REPORT.md -- C4 _processAutoRebuy section
- Skeptic verification: SKEPTIC-REVIEW.md -- F-05 detailed review

---

## BAF-Critical Path Verification Results

### Context

The BAF cache-overwrite bug's original location was in `_addClaimableEth` -> `_processAutoRebuy` in this module. Per D-07, the Mad Genius re-audited the entire chain from scratch as if the v4.4 EndgameModule fix does not exist. All 6 chains below represent every path from a Category B entry point to `_addClaimableEth` (C3).

### Chain Analysis Summary

| Chain | Path | Mad Genius Verdict | Skeptic Independent Verdict | Final |
|-------|------|-------------------|---------------------------|-------|
| 1 | B2 -> C11 -> C3 -> C4 (payDailyJackpot Phase 0) | SAFE | SAFE | **SAFE** |
| 2 | B2 -> C11 -> C3 -> C4 (payDailyJackpot Phase 1 carryover) | SAFE | SAFE | **SAFE** |
| 3 | B2 -> C9 -> C10 -> C12 -> C13 -> C14 -> C3 -> C4 (early-burn) | SAFE | SAFE | **SAFE** |
| 4 | B1 -> C12 -> C13 -> C14 -> C3 -> C4 (runTerminalJackpot) | SAFE | SAFE | **SAFE** |
| 5 | B5 -> C2 -> C3 -> C4 (consolidatePrizePools yield surplus) | SAFE (with F-01 INFO) | SAFE (with F-01 correction) | **SAFE** |
| 6 | B2 -> C1 (earlybird lootbox -- does NOT reach _addClaimableEth) | Not a BAF chain | Confirmed: not a BAF chain | **N/A** |

### Key Safety Patterns

The following design patterns prevent BAF-class cache-overwrite bugs across all chains:

1. **Fresh reads for pool writes:** Every `_setFuturePrizePool` / `_setNextPrizePool` call uses a fresh `_getFuturePrizePool()` / `_getNextPrizePool()` read (never a cached local).
2. **Return value tracking:** All 5 `_addClaimableEth` call sites use the return value (`claimableDelta`) for liability tracking, not the original `weiAmount` parameter. This correctly accounts for the auto-rebuy diversion.
3. **No stale writebacks:** `poolSnapshot` (B2 L353) is used read-only for budget calculation and never written back to storage.
4. **Aggregate-at-end pattern:** `claimablePool` updates happen after loops complete, using accumulated return values.

### Conclusion

All BAF-critical paths are SAFE in the current code. Both agents independently verified all 6 chains and agree on all verdicts. The original BAF cache-overwrite pattern (stale local written back after descendant modifies storage) does not exist in any ancestor function for any `_addClaimableEth` call site.

---

## Inline Assembly Verification Results

### _raritySymbolBatch (C20, lines 2050-2145)

| Check | Mad Genius Verdict | Skeptic Independent Verdict | Final |
|-------|-------------------|---------------------------|-------|
| Storage slot calculation | CORRECT | CORRECT | **CORRECT** |
| Array length accounting | CORRECT | CORRECT | **CORRECT** |
| Data slot calculation | CORRECT | CORRECT | **CORRECT** |
| LCG period (Knuth MMIX) | VALID (full period guaranteed by Hull-Dobell) | VALID | **VALID** |
| Memory safety | SAFE (scratch space only) | SAFE | **SAFE** |

**Detailed verification:**

1. **Level slot (L2110-2113):** `keccak256(abi.encode(lvl, traitBurnTicket.slot))` -- matches Solidity standard for `mapping(uint24 => address[][256])`. **CORRECT.**
2. **Per-trait slot (L2123):** `add(levelSlot, traitId)` -- matches Solidity fixed-array layout within mappings. `traitId` in [0,255], all 256 elements in consecutive slots. **CORRECT.**
3. **Array length (L2124-2126):** `sload(elem)` reads dynamic array length. `sstore(elem, newLen)` updates it. **CORRECT.**
4. **Data slot (L2129-2130):** `keccak256(abi.encode(elem))` gives data start for dynamic `address[]`. **CORRECT.**
5. **Write position (L2131):** `add(data, len)` gives next available slot. Each address occupies one full 32-byte slot. Loop writes `occurrences` entries starting from `dst`. **CORRECT.**
6. **Memory safety:** Only scratch space (0x00-0x3F) used for `mstore`. No interference with Solidity-managed memory. The `"memory-safe"` annotation is valid.

---

## Dismissed Findings (False Positives)

No findings were dismissed as false positives. All 5 Mad Genius findings were downgraded to INFO (documented in Confirmed Findings above as INFO-level observations). None were rejected outright.

| ID | Title | Mad Genius Verdict | Skeptic Verdict | Reason |
|----|-------|--------------------|-----------------|--------|
| F-01 | Yield surplus obligations snapshot staleness | INVESTIGATE (INFO) | DOWNGRADE TO INFO (with correction) | Snapshot read-only, directionally conservative, 8% buffer absorbs |
| F-02 | Assembly storage slot calculation non-obvious | INVESTIGATE (INFO) | DOWNGRADE TO INFO | Correct for declared type, contract non-upgradeable |
| F-03 | Processed counter approximation | INVESTIGATE (INFO) | DOWNGRADE TO INFO | Trait aesthetics only, no economic impact |
| F-04 | Double _getFuturePrizePool() read | INVESTIGATE (INFO) | DOWNGRADE TO INFO | 100 gas inefficiency, no correctness impact |
| F-05 | Zero takeProfit drops dust | INVESTIGATE (INFO) | DOWNGRADE TO INFO | Dust < ticketPrice/4, explicitly documented as intentional |

---

## Coverage Statistics

| Metric | Value |
|--------|-------|
| Functions on checklist | 55 |
| Category B analyzed | 7/7 |
| Category C analyzed | 28/28 |
| [MULTI-PARENT] standalone | 7/7 |
| [ASSEMBLY] verified | 1/1 |
| [BAF-CRITICAL] verified | 2/2 |
| [BAF-PATH] verified | 5/5 |
| Category D reviewed | 20/20 |
| BAF-critical chains verified | 6/6 |
| Taskmaster spot-checks | 5 |
| Storage write independent traces | 3 |
| Interrogation questions answered | 15 |
| Coverage percentage | 100% |

---

## Audit Trail

| Deliverable | Status | File |
|-------------|--------|------|
| Coverage Checklist | Complete (55/55 functions, all correctly categorized) | audit/unit-03/COVERAGE-CHECKLIST.md |
| Attack Report | Complete (7B + 28C analyzed, 5 findings) | audit/unit-03/ATTACK-REPORT.md |
| Coverage Review | PASS (100% coverage, 0 gaps) | audit/unit-03/COVERAGE-REVIEW.md |
| Skeptic Review | Complete (0 CONFIRMED, 5 DOWNGRADE TO INFO) | audit/unit-03/SKEPTIC-REVIEW.md |
| Final Findings | This document | audit/unit-03/UNIT-03-FINDINGS.md |

---

*Unit 3 audit complete. 0 confirmed vulnerabilities. All BAF-critical paths verified SAFE by both agents. Inline assembly verified CORRECT by both agents. 100% coverage confirmed by Taskmaster. Ready for master FINDINGS.md consolidation at Phase 119.*
