# Phase 152 Plan 01: Delta Adversarial Audit Findings

**Audit scope:** All functions changed/added by Phase 151 (Endgame Flag Implementation) across 4 contracts.
**Methodology:** Per-function adversarial verdict (SAFE/VULNERABLE/INFO), RNG backward-trace, storage layout verification via `forge inspect`.
**Date:** 2026-03-31

---

## Section 1: Per-Function Verdict Table

| # | Contract | Function / Variable | Change Type | Verdict | Rationale |
|---|----------|-------------------|-------------|---------|-----------|
| 1 | GameStorage | `gameOverPossible` (line 341) | NEW | SAFE | Bool packed in Slot 1 at byte offset 25 (immediately after `prizePoolFrozen` at byte 24). Verified via `forge inspect DegenerusGameStorage storage-layout`: Slot 1, offset 25, 1 byte. No storage collision -- occupies previously unused padding bytes [25:32]. Shares SLOAD with `prizePoolFrozen`, `ticketsFullyProcessed`, `ticketWriteSlot`, `price`, `purchaseStartDay` -- zero additional SLOAD cost for reads/writes within the same transaction that already touches Slot 1. |
| 2 | AdvanceModule | `DECAY_RATE` (line 106) | NEW | SAFE | `0.9925 ether` = 992500000000000000 = (1 - 0.0075) in WAD scale. Correct representation of 0.75% daily decay. `private` visibility is correct -- only consumed by `_wadPow` and `_projectedDrip` in the same file. As a constant, it occupies no storage slot and is inlined at compile time. |
| 3 | AdvanceModule | `_wadPow` (lines 1616-1626) | NEW | SAFE | Repeated-squaring exponentiation in 1e18 (WAD) scale. For base=0.9925e18 and max exp=120 (120 days): 7 iterations (2^7=128 > 120). Each iteration: `(result * base) / 1e18` where both operands are < 1e18 (DECAY_RATE < 1 ether, result starts at 1e18 and monotonically decreases). Product never exceeds 1e36, well within uint256 range (< 2^256). Result precision: at exp=120, 0.9925^120 ~= 0.406, yielding ~4.06e17 -- 17 digits of precision, acceptable for comparison against deficit. Uses `1 ether` (= 1e18) as WAD unit, consistent with Solidity convention. No overflow, no underflow, no division by zero. |
| 4 | AdvanceModule | `_projectedDrip` (lines 1630-1637) | NEW | SAFE | Closed-form geometric series: `futurePool * (1 - 0.9925^n)`. Handles `daysRemaining == 0` with early return of 0 (correct -- zero days means zero drip). For `daysRemaining > 0`: `decayN = _wadPow(DECAY_RATE, daysRemaining)` is always < 1e18 because DECAY_RATE < 1e18 and any positive power of a value < 1 is < 1. Therefore `1 ether - decayN` is always positive, no underflow. `futurePool * (1 ether - decayN)` -- futurePool is bounded by total ETH in the protocol (< 2^128 in practice), and `(1 ether - decayN) < 1e18`, so product < 2^128 * 1e18 < 2^188, well within uint256. Division by `1 ether` is safe (non-zero constant). |
| 5 | AdvanceModule | `_evaluateGameOverPossible` (lines 1642-1659) | NEW | SAFE | L10+ gate: `lvl < 10` clears flag and returns unconditionally -- correct per FLAG-04 (no flag activity below L10). Deficit calculation: `target - nextPool` is safe because the `nextPool >= target` check (line 1649) returns first, preventing underflow. `daysRemaining` calculation: `(levelStartTime + 120 days - block.timestamp) / 1 days` -- safe from underflow because `_handleGameOverPath` (line 160) returns before reaching this code if `block.timestamp >= levelStartTime + 120 days`. Flag set/clear: `gameOverPossible = _projectedDrip(...) < deficit` -- assignment based on boolean comparison, no possibility of inconsistent state. Matches FLAG-01 (set at purchase-phase entry), FLAG-02 (re-check daily), FLAG-04 (L10+ only). |
| 6 | AdvanceModule | `advanceGame` turbo path (line 154) | MODIFIED | SAFE | `gameOverPossible = false` placed after `lastPurchaseDay = true` and `compressedJackpotFlag = 2` within the turbo guard `purchaseDays <= 1 && _getNextPrizePool() >= levelPrizePool[lvl]`. FLAG-03 compliance: when target is met on day 0-1 (turbo), the flag is cleared because the level will definitely transition (target met means no endgame scenario). No other state affected -- the three writes are all independent Slot 0 / Slot 1 variables. Attack vector: an attacker cannot force turbo by manipulating `_getNextPrizePool()` in the same transaction (nextPool accumulates from prior transactions). |
| 7 | AdvanceModule | `advanceGame` phase transition (line 289) | MODIFIED | SAFE | `_evaluateGameOverPossible(lvl, purchaseLevel)` called at `STAGE_TRANSITION_DONE` after `phaseTransitionActive = false`, `_unlockRng(day)`, `purchaseStartDay = day`, `jackpotPhaseFlag = false`. Timing is correct: this is purchase-phase entry, exactly when FLAG-01 requires evaluation. **lvl value analysis:** `lvl` is cached from `level` at line 144. During jackpot-to-purchase transition, `level` was incremented by `_requestRng` during the jackpot-ending RNG request. So when transitioning from L9 jackpot to L10 purchase, `lvl = 10` (post-increment). At L9->L10: `_evaluateGameOverPossible(10, 11)` -- `lvl < 10` is false, so full evaluation fires on L10 purchase-phase entry. This is the correct first evaluation point. (For L8->L9: `lvl = 9`, `lvl < 10` is true, unconditional clear.) |
| 8 | AdvanceModule | `advanceGame` daily re-check (lines 326-328) | MODIFIED | SAFE | `if (gameOverPossible) { _evaluateGameOverPossible(lvl, purchaseLevel); }` -- gas optimization: skips SLOAD-heavy evaluation when flag is already false. Location: inside `if (!inJackpot)` (purchase phase only) and `if (!lastPurchaseDay)` (pre-target only). FLAG-04 compliant: no evaluation during jackpot phase or after target met. FLAG-02 compliant: re-checks daily to potentially clear if new ETH has arrived in futurePool. Placement before target check at line 329: ensures flag is cleared before `lastPurchaseDay` could be set on the same call. Order-of-operations is correct (see Section 5 for detailed trace). |
| 9 | MintModule | `_purchaseCoinFor` (line 611) | MODIFIED | SAFE | `if (gameOverPossible) revert GameOverPossible()` is inside `if (ticketQuantity != 0)` block (line 609), confirming it only fires on the BURNIE ticket path. ETH ticket purchases (where `ticketQuantity == 0` and ETH is sent) bypass this check entirely -- ENF-03 compliant. The error `GameOverPossible` (line 67) replaces the removed `CoinPurchaseCutoff`. Verified: no remnants of `CoinPurchaseCutoff`, `COIN_PURCHASE_CUTOFF`, or `COIN_PURCHASE_CUTOFF_LVL0` exist in the codebase (grep confirms 0 matches across all contracts). Attack vector: a player cannot bypass the flag by calling a different purchase function -- all BURNIE ticket purchases route through `_purchaseCoinFor`. Griefing analysis: the flag cannot be used to grief because only `advanceGame` (permissionless bounty call) can set it, and setting requires a genuine drip-vs-deficit shortfall. |
| 10 | LootboxModule | BURNIE resolution (lines 643-646) | MODIFIED | SAFE | `if (gameOverPossible && targetLevel == currentLevel)` redirects to `currentLevel | TICKET_FAR_FUTURE_BIT` (bit 22 far-future key space). Near-future rolls (`targetLevel != currentLevel`, i.e., `currentLevel+1` through `currentLevel+6`) pass through unaffected -- ENF-02 compliant. ETH lootbox path: this code is in the BURNIE resolution branch only; ETH lootbox resolution uses a separate code path with no `gameOverPossible` reference -- ENF-03 compliant. Verified: `BURNIE_LOOT_CUTOFF` and `BURNIE_LOOT_CUTOFF_LVL0` fully absent from codebase (grep confirms 0 matches). The redirect uses `currentLevel | TICKET_FAR_FUTURE_BIT` directly instead of `_tqFarFutureKey(currentLevel)` helper, but both produce identical results (`lvl | TICKET_FAR_FUTURE_BIT`). Attack vector: an attacker purchasing a lootbox when `gameOverPossible` is true gets current-level tickets redirected to far-future -- this is protective (prevents zero-ETH tickets from competing for terminal jackpot), not exploitable. |

**Summary: 10/10 functions audited. 10 SAFE, 0 VULNERABLE, 0 INFO in per-function verdicts.**

---

## Section 2: Storage Layout Verification

Verified via `forge inspect DegenerusGameStorage storage-layout`:

### Slot 1 Layout (from forge inspect)

| Name | Type | Slot | Offset | Bytes |
|------|------|------|--------|-------|
| purchaseStartDay | uint48 | 1 | 0 | 6 |
| price | uint128 | 1 | 6 | 16 |
| ticketWriteSlot | uint8 | 1 | 22 | 1 |
| ticketsFullyProcessed | bool | 1 | 23 | 1 |
| prizePoolFrozen | bool | 1 | 24 | 1 |
| gameOverPossible | bool | 1 | 25 | 1 |

**Verification results:**
- `gameOverPossible` is in Slot 1 at byte offset 25 (1 byte) -- immediately after `prizePoolFrozen` at offset 24
- No storage gaps: offsets are contiguous (0, 6, 22, 23, 24, 25) with `price` spanning 6-21
- No collisions: total used bytes = 26 out of 32 available in the slot
- Bytes 26-31 remain as padding (6 bytes unused)
- Packing is correct: `gameOverPossible` shares the same SLOAD/SSTORE as other Slot 1 variables

**No storage regressions introduced.**

---

## Section 3: Naming Consistency Verification (D-04)

Searched all 4 changed contracts for naming patterns:

| Pattern | Expected | Matches | Status |
|---------|----------|---------|--------|
| `gameOverPossible` (bool variable) | Consistent across all files | 14 matches: GameStorage (1 declaration), AdvanceModule (7 read/write sites), MintModule (1 read), LootboxModule (1 read + 1 comment) | PASS |
| `GameOverPossible` (error) | Single definition in MintModule | 2 matches: MintModule line 67 (declaration), line 611 (revert) | PASS |
| `endgameFlag` (old plan name) | Zero matches | 0 matches | PASS |
| `EndgameFlagActive` (old plan name) | Zero matches | 0 matches | PASS |
| `_evaluateGameOverPossible` (function) | AdvanceModule only | 3 matches: line 289 (call), line 327 (call), line 1642 (definition) | PASS |

**Naming is consistent across all 4 contracts. No stale references to plan-era names.**

---

## Section 4: Stale Comment Check

The Slot 1 layout table in DegenerusGameStorage.sol (lines 55-65) contains:

```
| [24:25] prizePoolFrozen          bool     Prize pool freeze active flag      |
| [25:32] <padding>                         7 bytes unused                     |
```

**Finding V11-001 (INFO):** The comment still shows bytes 25-31 as `<padding>` and does not document `gameOverPossible` at byte 25. The actual layout (verified by `forge inspect`) has `gameOverPossible` at offset 25. The comment should read:

```
| [24:25] prizePoolFrozen          bool     Prize pool freeze active flag      |
| [25:26] gameOverPossible         bool     Drip-deficit endgame gate flag     |
| [26:32] <padding>                         6 bytes unused                     |
```

**Impact:** Documentation only. No runtime or ABI impact. The variable declaration and NatSpec at line 336-341 are correct. The layout table is a developer reference comment.

**Total Slot 1 used bytes:** Updated from "25 bytes used (7 bytes padding)" to "26 bytes used (6 bytes padding)".

---

## Section 5: Verifier Edge Cases from Phase 151

### Edge Case 1: Normal-daily lastPurchaseDay indirect clear order-of-operations

**Question:** When `gameOverPossible` is true and `_getNextPrizePool() >= levelPrizePool[...]` becomes true on the same advanceGame call, is `gameOverPossible` correctly false before `lastPurchaseDay = true`?

**Trace:**

1. Line 322: `if (!lastPurchaseDay)` -- enters because `lastPurchaseDay` is false
2. Line 323-324: `payDailyJackpot(...)` and `_payDailyCoinJackpot(...)` execute
3. Line 326: `if (gameOverPossible)` -- true, enters block
4. Line 327: `_evaluateGameOverPossible(lvl, purchaseLevel)` executes
5. Inside `_evaluateGameOverPossible` (line 1647-1651): reads `nextPool = _getNextPrizePool()`, reads `target = levelPrizePool[purchaseLevel - 1]`. If `nextPool >= target`, line 1650 sets `gameOverPossible = false` and returns.
6. Back at line 329: `if (_getNextPrizePool() >= levelPrizePool[purchaseLevel - 1])` -- same condition. If true, line 332: `lastPurchaseDay = true`.

**Conclusion:** `_evaluateGameOverPossible` at line 327 runs BEFORE the target check at line 329. When `nextPool >= target` is true, `_evaluateGameOverPossible` clears the flag (line 1650) before `lastPurchaseDay` is set (line 332). The flag is always false when `lastPurchaseDay` becomes true on the normal-daily path.

**Verdict:** SAFE. Order-of-operations is correct. The indirect clear mechanism works as intended.

### Edge Case 2: Exact value of `lvl` at L9->L10 phase transition

**Question:** When transitioning from level 9 jackpot to level 10 purchase phase, what is `lvl` at line 289 when `_evaluateGameOverPossible(lvl, purchaseLevel)` is called?

**Trace:**

1. Line 144: `uint24 lvl = level;` -- caches the storage `level` into a stack variable at the start of `advanceGame`
2. The `level` storage variable is incremented by `_requestRng` during the jackpot-ending RNG request (when `lastPurchaseDay` was true on the prior call, the RNG request includes a level pre-increment)
3. When `advanceGame` is called and enters the phase-transition path (line 260: `if (phaseTransitionActive)`), `level` has already been incremented by the prior RNG request
4. Therefore at L9->L10 transition: `level = 10` in storage, `lvl = 10` (cached at line 144)
5. Line 289: `_evaluateGameOverPossible(10, purchaseLevel)` where `purchaseLevel = 11` (from line 159: `lvl + 1`)

**Inside `_evaluateGameOverPossible(10, 11)`:**
- Line 1643: `if (lvl < 10)` -- false (10 is not < 10)
- Full evaluation fires: reads nextPool vs target for level 10, computes drip projection

**Conclusion:** At the L9->L10 transition, `lvl = 10`, and the first real endgame evaluation fires immediately on purchase-phase entry. This is correct -- L10 is the first level where the endgame flag can be meaningful.

**For L8->L9:** `lvl = 9`, `lvl < 10` is true, unconditional clear (no evaluation needed, correct).

**Verdict:** SAFE. The `lvl` value at phase transition is the post-increment value, and the L10+ gate works correctly at the L9->L10 boundary.

---

## Section 6: RNG Commitment Window Analysis

Per D-05 through D-08, traced BACKWARD from every consumer of `gameOverPossible`.

Every RNG audit traced BACKWARD from each consumer to verify the flag value was deterministic or non-exploitable at commitment time.

### Path 1: MintModule._purchaseCoinFor (line 611)

**Consumer context:** `gameOverPossible` is read during a user-initiated `purchaseCoinTickets` call. This is NOT during VRF fulfillment -- it is a direct user transaction.

**Backward trace:** The flag value was set during the most recent `advanceGame` call. The user cannot change it between their commitment and their purchase because only `advanceGame` writes the flag. `advanceGame` is a permissionless bounty call that anyone can trigger, but:
1. The flag state depends on `_getNextPrizePool()`, `levelPrizePool`, `_getFuturePrizePool()`, `levelStartTime`, and `block.timestamp` -- none of which are controllable by a single actor within one transaction
2. Calling `advanceGame` to flip the flag requires the on-chain state to genuinely warrant a flag change (drip projection vs deficit)
3. There is no VRF involvement in this path -- the purchase is synchronous

**Verdict:** SAFE. No commitment window issue.

### Path 2: LootboxModule BURNIE Resolution (lines 643-646)

**Consumer context:** `gameOverPossible` is read during `_resolveLootbox`, which is called from VRF fulfillment (`rawFulfillRandomWords`).

**Backward trace:** When the user called `purchaseLootbox`, was `gameOverPossible` already set? The flag could change between lootbox purchase (VRF request) and lootbox resolution (VRF fulfillment) if someone calls `advanceGame` in between.

**Analysis:**
1. The lootbox purchase does not commit to a specific flag state -- the purchase commits to receiving lootbox rewards, not to a specific target level
2. The redirect is a PROTECTIVE measure: it prevents zero-ETH tickets from competing for the terminal jackpot, which would dilute legitimate participants
3. The flag changing between purchase and resolution is equivalent to the old elapsed-time check changing (time always advances between request and fulfillment)
4. An attacker cannot profitably manipulate the flag -- calling `advanceGame` is permissionless but the flag state depends entirely on on-chain `futurePool`/`nextPool`/`levelPrizePool` which are not controllable by a single actor
5. Even if an attacker could flip the flag, the redirect only affects current-level tickets (near-future rolls are unaffected), and the redirected tickets still participate in far-future jackpots -- they are not destroyed

**Verdict:** SAFE. The commitment window change is non-exploitable (protective redirect, not value extraction).

### Path 3: AdvanceModule._evaluateGameOverPossible (lines 289, 326-328)

**Consumer context:** `gameOverPossible` is written ONLY inside `advanceGame`, which is a permissionless bounty call -- NOT during VRF fulfillment.

**Backward trace:** Does the VRF word influence the flag? The function reads:
- `_getNextPrizePool()` -- reads `nextPrizePool` storage (accumulated from mints, not RNG-dependent)
- `levelPrizePool[purchaseLevel - 1]` -- reads a fixed target for the level
- `_getFuturePrizePool()` -- reads `futurePrizePool` storage (accumulated from skims, not RNG-dependent)
- `levelStartTime` -- set at phase transition, not RNG-dependent
- `block.timestamp` -- block context, not RNG-dependent

None of these depend on the VRF random word. The evaluation happens BEFORE `_requestRng` / `_unlockRng` in the `advanceGame` flow (lines 289 and 326-328 are both before the RNG gate at line 246 on subsequent calls, and the evaluation uses no RNG-derived values).

**Verdict:** SAFE. No commitment window issue -- flag evaluation is fully deterministic from on-chain state with no RNG dependency.

### RNG Commitment Window Summary

| # | Consumer | Read Context | Flag Writer | Manipulable? | Verdict |
|---|----------|-------------|-------------|-------------|---------|
| 1 | MintModule._purchaseCoinFor | User tx (not VRF) | advanceGame | No -- requires genuine on-chain state change | SAFE |
| 2 | LootboxModule BURNIE resolution | VRF fulfillment | advanceGame | No -- protective redirect, not exploitable | SAFE |
| 3 | AdvanceModule._evaluateGameOverPossible | advanceGame (not VRF) | Self | No -- deterministic from on-chain state, no RNG input | SAFE |

**All 3 paths verified SAFE. No player-controllable state between VRF request and fulfillment can exploit flag-dependent logic.**

---

## Overall Audit Summary

| Category | Count |
|----------|-------|
| Functions audited | 10 |
| SAFE verdicts | 10 |
| VULNERABLE verdicts | 0 |
| INFO findings | 1 (V11-001: stale Slot 1 layout comment) |
| RNG paths analyzed | 3 |
| RNG paths SAFE | 3 |
| Storage layout verified | Yes (forge inspect) |
| Naming consistency | Verified (0 stale references) |
| Phase 151 edge cases resolved | 2/2 |

**Conclusion:** Zero security regressions from the Phase 151 endgame flag implementation. All changed functions are SAFE. RNG commitment window is clean for all flag-dependent paths. Storage layout is correct with no collisions.

---

*Audit completed: 2026-03-31*
*Auditor: Claude (gsd-executor)*
