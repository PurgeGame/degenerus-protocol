# REDM-04: Activity Score Snapshot Immutability

**Requirement:** Activity score snapshot at submission is immutable through resolution.

**Contracts analyzed:**
- `StakedDegenerusStonk.sol` -- snapshot write (lines 759-762), snapshot read (line 581), partial claim (lines 611-617), decode + pass (lines 621-624)
- `DegenerusGame.sol` -- cross-contract routing (lines 1791-1845)
- `DegenerusGameLootboxModule.sol` -- snapshot consumption (lines 717-750), EV multiplier (lines 476-501), EV cap (lines 503-545)

---

## Phase 1: Snapshot (Write Path)

### 1. Guard Condition and +1 Encoding (Lines 759-762)

**Code:**
```solidity
// StakedDegenerusStonk.sol lines 759-762
// Snapshot activity score on first burn of period (0 = not yet set, stored as score + 1)
if (claim.activityScore == 0) {
    claim.activityScore = uint16(game.playerActivityScore(beneficiary)) + 1;
}
```

**Analysis:**

1. **Guard condition (`activityScore == 0` means "not yet set"):** The `PendingRedemption` struct field `activityScore` is `uint16` (line 186). A fresh struct (from `delete` on line 613 or never written) has `activityScore == 0`. The guard `== 0` means "not yet snapshotted." Once set to a non-zero value, the guard prevents any subsequent overwrite. **SAFE.**

2. **+1 encoding correctness:** The value stored is `uint16(game.playerActivityScore(beneficiary)) + 1`. This means:
   - If `playerActivityScore` returns 0 (inactive player): stored value = 0 + 1 = 1 (non-zero, guard works correctly on subsequent burns in the same period).
   - If `playerActivityScore` returns 6000 (neutral): stored value = 6001.
   - The +1 ensures zero can unambiguously represent "not yet set."
   **SAFE.**

3. **Write-once per period:** On the first burn in a period, `claim.activityScore == 0` is true, so it gets set. On subsequent burns in the same period, `claim.activityScore != 0`, so the guard prevents overwrite. The period check on line 748 (`claim.periodIndex != 0 && claim.periodIndex != currentPeriod`) ensures that stacking across periods is blocked (reverts with `UnresolvedClaim`). **SAFE.**

4. **Edge case -- playerActivityScore returns 0:** Stored value = 0 + 1 = 1. Non-zero, guard works. On claim decode (line 621): `1 - 1 = 0`. Original score correctly recovered. **SAFE.**

5. **Edge case -- uint16 overflow risk:** If `playerActivityScore()` returns >= 65535, then `uint16(score) + 1` could wrap to 0, causing the guard to fail and allowing re-snapshotting on the next burn.

   **`playerActivityScore()` return range analysis** (DegenerusGame.sol lines 2482-2563):

   The function computes `bonusBps` via addition of components. Maximum values by path:

   **Deity pass path** (highest possible):
   | Component | Max Value (bps) | Source |
   |-----------|----------------|--------|
   | Deity streak floor | 5000 | `50 * 100` (line 2514) |
   | Deity mint count floor | 2500 | `25 * 100` (line 2515) |
   | Quest streak | 10000 | `min(questStreak, 100) * 100` (line 2543) |
   | Affiliate bonus | 5000 | `min(points, 50) * 100` (line 2548-2549, AFFILIATE_BONUS_MAX=50) |
   | Deity pass activity bonus | 8000 | `DEITY_PASS_ACTIVITY_BONUS_BPS` (line 2552, constant = 8000) |
   | **Total** | **30500** | |

   **Non-deity pass path** (highest possible):
   | Component | Max Value (bps) | Source |
   |-----------|----------------|--------|
   | Mint streak | 5000 | `min(streak, 50) * 100` (line 2518) |
   | Mint count | 2500 | `(mintCount * 25) / currLevel`, max 25 points (line 2520) |
   | Quest streak | 10000 | `min(questStreak, 100) * 100` (line 2543) |
   | Affiliate bonus | 5000 | `min(points, 50) * 100` (line 2548-2549) |
   | Whale bundle (100-level) | 4000 | `bundleType == 3` (line 2558) |
   | **Total** | **26500** | |

   **Maximum possible score: 30500 bps** (deity pass path).

   `uint16(30500) + 1 = 30501`. This fits trivially in uint16 (max 65535).

   **No overflow is possible.** The maximum score (30500) plus the +1 encoding (30501) is well within uint16 range. Even if every component were at max simultaneously, the sum is 30501, far below 65535.

   **Verdict: SAFE -- No uint16 overflow risk.**

### 2. No Mutation Paths

**Search results for all writes to `activityScore` in StakedDegenerusStonk.sol:**

| Line | Context | Type |
|------|---------|------|
| 186 | `uint16 activityScore;` | Struct field declaration |
| 581 | `uint16 claimActivityScore = claim.activityScore;` | **Read** (local variable copy) |
| 760 | `if (claim.activityScore == 0)` | **Read** (guard check) |
| 761 | `claim.activityScore = uint16(...) + 1;` | **Write** (only write path) |
| 613 | `delete pendingRedemptions[player];` | **Implicit zero** (full struct delete) |

The only explicit write is line 761, gated by `claim.activityScore == 0`. The only other modification is `delete pendingRedemptions[player]` (line 613), which zeros the entire struct -- but this happens in `claimRedemption` after the snapshot has already been consumed into a local variable (line 581). No other code path modifies `claim.activityScore`.

**Verdict: SAFE -- Single write path, guarded by == 0.**

---

## Phase 2: Consumption (Read Path)

### 3. Snapshot Read Before Delete (Line 581)

**Code:**
```solidity
// StakedDegenerusStonk.sol line 581
uint16 claimActivityScore = claim.activityScore;
```

**Analysis:**

Line 581 reads `claim.activityScore` from storage into local variable `claimActivityScore` before any struct modification. The subsequent operations that modify or delete the struct are:

| Line | Operation | After line 581? |
|------|-----------|-----------------|
| 609 | `pendingRedemptionEthValue -= totalRolledEth` | Yes (global, not struct) |
| 613 | `delete pendingRedemptions[player]` | Yes -- zeros struct |
| 616 | `claim.ethValueOwed = 0` | Yes -- partial clear |

The local variable `claimActivityScore` is a stack copy (uint16 value type). Once captured, it is immune to any storage changes. The struct delete on line 613 zeros `claim.activityScore` in storage, but the local copy persists.

**Verdict: SAFE -- Local capture before storage mutation.**

### 4. +1 Encoding Reversal (Line 621)

**Code:**
```solidity
// StakedDegenerusStonk.sol line 621
uint16 actScore = claimActivityScore > 0 ? claimActivityScore - 1 : 0;
```

**Analysis:**

- **Normal case:** `claimActivityScore` was stored as `score + 1` (line 761). Subtracting 1 recovers the original score. If original score was 6000, stored as 6001, decoded as 6000. Correct.
- **Edge case claimActivityScore == 1:** Original score was 0. `actScore = 1 - 1 = 0`. Correct.
- **Edge case claimActivityScore == 0:** This means "not yet set." Per the flow, this should never happen because:
  1. Line 574 checks `claim.periodIndex == 0` and reverts with `NoClaim()` if no claim exists.
  2. If a claim exists (`periodIndex != 0`), then `_submitGamblingClaimFrom` was called, which always sets `activityScore` on first burn (line 760-761). So `activityScore >= 1`.
  3. The ternary safely handles this impossible case by returning 0.

**Verdict: SAFE -- +1 encoding correctly reversed; impossible edge case handled gracefully.**

### 5. Parameter Passing to Game (Line 624)

**Code:**
```solidity
// StakedDegenerusStonk.sol lines 620-624
if (lootboxEth != 0) {
    uint16 actScore = claimActivityScore > 0 ? claimActivityScore - 1 : 0;
    uint256 rngWord = game.rngWordForDay(claimPeriodIndex);
    uint256 entropy = uint256(keccak256(abi.encode(rngWord, player)));
    game.resolveRedemptionLootbox(player, lootboxEth, entropy, actScore);
}
```

`actScore` (uint16) is passed as the 4th argument to `game.resolveRedemptionLootbox()`. The function signature in DegenerusGame.sol (line 1798-1803) accepts `uint16 activityScore` as its 4th parameter. Types match exactly.

**Verdict: SAFE -- Type-correct parameter passing.**

---

## Phase 3: Cross-Contract Flow

### 6. Game.resolveRedemptionLootbox (DegenerusGame.sol lines 1791-1845)

**Code:**
```solidity
// DegenerusGame.sol lines 1798-1803
function resolveRedemptionLootbox(
    address player,
    uint256 amount,
    uint256 rngWord,
    uint16 activityScore   // <-- received from sDGNRS
) external {
```

**Parameter flow:**
- `activityScore` is received as `uint16` (line 1803).
- No transformation is applied to `activityScore` between receipt and forwarding.
- It is passed directly to the LootboxModule delegatecall at line 1838:

```solidity
// DegenerusGame.sol lines 1830-1839
.delegatecall(
    abi.encodeWithSelector(
        IDegenerusGameLootboxModule
            .resolveRedemptionLootbox
            .selector,
        player,
        box,
        rngWord,
        activityScore       // <-- forwarded unchanged
    )
);
```

The function does NOT read `playerActivityScore(player)` (the live score). It uses only the snapshotted `activityScore` parameter passed from sDGNRS.

**Verdict: SAFE -- Pass-through with no transformation, no live-score read.**

### 7. LootboxModule.resolveRedemptionLootbox (Lines 717-750)

**Code:**
```solidity
// DegenerusGameLootboxModule.sol lines 724, 732
function resolveRedemptionLootbox(
    address player, uint256 amount, uint256 rngWord,
    uint16 activityScore    // <-- received from Game delegatecall
) external {
    // ...
    uint256 evMultiplierBps = _lootboxEvMultiplierFromScore(uint256(activityScore));
    // ...
}
```

**Analysis:**

1. `activityScore` (uint16) is cast to uint256 for `_lootboxEvMultiplierFromScore()`. This is a widening cast -- no data loss.

2. `_lootboxEvMultiplierFromScore` (lines 476-501) interprets the score correctly:
   - Score 0 (inactive): `0 <= 6000` (NEUTRAL_BPS) => enters first branch. Returns `8000 + (0 * 2000) / 6000 = 8000` (80% EV). Correct.
   - Score 6000 (neutral): `6000 <= 6000` => enters first branch. Returns `8000 + (6000 * 2000) / 6000 = 10000` (100% EV). Correct.
   - Score 25500 (max): `25500 >= 25500` (MAX_BPS) => returns `13500` (135% EV). Correct.
   - Score 30500 (deity max, exceeds lootbox MAX_BPS): `30500 >= 25500` => returns `13500` (135% EV). Capped correctly.

3. **No live-score read:** This function does NOT call `IDegenerusGame(address(this)).playerActivityScore(player)`. Compare with `_lootboxEvMultiplierBps()` (line 471-473), which DOES read the live score -- but that function is used by the regular lootbox path, not the redemption path. The redemption path exclusively uses the snapshotted score parameter.

**Verdict: SAFE -- Snapshotted score consumed correctly; no live-score leakage.**

### 8. EV Cap Application (Line 733)

**Code:**
```solidity
// DegenerusGameLootboxModule.sol line 733
uint256 scaledAmount = _applyEvMultiplierWithCap(player, currentLevel, amount, evMultiplierBps);
```

**`_applyEvMultiplierWithCap` analysis (lines 503-545):**

- Per-account-per-level cap of 10 ETH (`LOOTBOX_EV_BENEFIT_CAP = 10 ether`, line 332-333).
- Tracks usage via `lootboxEvBenefitUsedByLevel[player][lvl]` (line 523).
- When cap exhausted: returns `amount` unscaled (100% EV neutral).
- When partially remaining: splits `amount` into adjusted (gets EV multiplier) and neutral (gets 100%) portions.

**Can activity score manipulation bypass the cap?** No. The cap is applied on the `amount` dimension (ETH volume), not the score dimension. A higher activity score increases `evMultiplierBps` but does not affect the 10 ETH cap on how much ETH gets the adjusted multiplier. Even if a player could manipulate their activity score (which they cannot, since it is snapshotted), they would still be limited to 10 ETH of EV-adjusted lootbox rewards per level.

**Verdict: SAFE -- Cap operates on ETH volume, independent of score value.**

---

## Phase 4: Partial Claim Interaction

### 9. Partial Claim Preserves Activity Score (Lines 611-617)

**Code:**
```solidity
// StakedDegenerusStonk.sol lines 611-617
if (flipResolved) {
    // Full claim: clear entirely
    delete pendingRedemptions[player];    // zeros ALL fields including activityScore
} else {
    // Partial claim: clear ETH portion, keep BURNIE for later
    claim.ethValueOwed = 0;              // only zeros ethValueOwed
}
```

**Analysis:**

**Case A: Coinflip resolved (`flipResolved == true`):**
- `delete pendingRedemptions[player]` zeros the entire struct.
- `activityScore` is zeroed in storage, but the local copy `claimActivityScore` (captured at line 581) was already consumed by lines 621-624 before the delete.
- The player's lootbox has already been resolved. The struct delete is cleanup only.
- **SAFE.**

**Case B: Coinflip unresolved (`flipResolved == false`):**
- Only `claim.ethValueOwed = 0` is written.
- `claim.activityScore` remains intact in storage.
- The player must return for a second `claimRedemption()` call to claim BURNIE once the coinflip resolves.

**Second claim path trace:**
1. Player calls `claimRedemption()` again.
2. Line 574: `claim.periodIndex != 0` -- passes (still set from first claim).
3. Line 577: `period.roll != 0` -- passes (period was already resolved).
4. Line 581: `claimActivityScore = claim.activityScore` -- reads the still-intact snapshot.
5. Line 584: `totalRolledEth = (claim.ethValueOwed * roll) / 100`. But `claim.ethValueOwed == 0` (zeroed on first claim). So `totalRolledEth == 0`.
6. Line 593: `ethDirect = 0 / 2 = 0`. `lootboxEth = 0 - 0 = 0`.
7. Line 620: `if (lootboxEth != 0)` -- **FALSE**. `resolveRedemptionLootbox` is NOT called.
8. The activity score is effectively consumed only once, even in the split-claim case.

**The second claim only processes BURNIE (via coinflip resolution at lines 601-605). The lootbox path is skipped because `lootboxEth == 0`. This means:**
- The snapshotted activity score is consumed exactly once for lootbox EV calculation.
- On the second claim, the activity score is technically still in storage but never read for any consequential purpose.
- The `delete pendingRedemptions[player]` on line 613 (now `flipResolved == true`) cleans it up.

**Verdict: SAFE -- Activity score consumed exactly once; partial claim does not re-trigger lootbox resolution.**

---

## Verdicts

| Sub-finding | Verdict | Evidence |
|-------------|---------|----------|
| Guard condition (`activityScore == 0`) | **SAFE** | Line 760: write-once semantics; 0 is unambiguous "not set" due to +1 encoding |
| +1 encoding at write | **SAFE** | Line 761: `uint16(score) + 1`; max score 30500 + 1 = 30501, well within uint16 max (65535) |
| +1 encoding at read | **SAFE** | Line 621: `claimActivityScore - 1` correctly reverses; edge cases (0, 1) handled |
| Snapshot read before delete | **SAFE** | Line 581 captures to local before line 613 deletes struct |
| No mutation paths | **SAFE** | Only write at line 761, guarded by `== 0`; no other write to `claim.activityScore` |
| Cross-contract pass-through | **SAFE** | Game (line 1838) forwards unchanged; LootboxModule (line 732) consumes; no live-score read |
| EV cap independence | **SAFE** | 10 ETH cap on volume, not score; score manipulation cannot bypass cap |
| Partial claim interaction | **SAFE** | Second claim has `ethValueOwed == 0` => `lootboxEth == 0` => lootbox path skipped |
| uint16 overflow risk | **SAFE** | Max `playerActivityScore` = 30500 bps (deity path); stored as 30501; uint16 max = 65535 |

## Overall Verdict: SAFE

**REDM-04 is SAFE.** The activity score is:
1. **Snapshotted once** per period on first burn (line 761), guarded by `activityScore == 0`
2. **Never mutated** between snapshot and consumption (no other write paths exist)
3. **Captured locally** (line 581) before struct delete/modification (lines 613, 616)
4. **Correctly decoded** (line 621) by reversing the +1 encoding
5. **Passed unchanged** through the cross-contract chain: sDGNRS (line 624) -> Game (line 1838) -> LootboxModule (line 732)
6. **Consumed exactly once** even in the split-claim case (second claim has `lootboxEth == 0`)

**Full data flow trace:**
```
Write:   _submitGamblingClaimFrom:761  claim.activityScore = uint16(score) + 1
                                       [guard: claim.activityScore == 0]
                    |
                    v  (stored in PendingRedemption struct, slot bits [240:255])
                    |
Read:    claimRedemption:581           claimActivityScore = claim.activityScore
                    |                  [local variable capture]
                    v
Decode:  claimRedemption:621           actScore = claimActivityScore - 1
                    |                  [+1 encoding reversed]
                    v
Pass:    claimRedemption:624           game.resolveRedemptionLootbox(..., actScore)
                    |
                    v
Route:   Game:1838                     delegatecall LootboxModule(..., activityScore)
                    |                  [pass-through, no transformation]
                    v
Consume: LootboxModule:732            _lootboxEvMultiplierFromScore(uint256(activityScore))
                    |                  [uint16 -> uint256 widening, then linear interpolation]
                    v
Apply:   LootboxModule:733            _applyEvMultiplierWithCap(player, level, amount, evMultiplierBps)
                                       [10 ETH per-account-per-level cap]
```

**No findings.** The activity score snapshot is immutable from write through consumption.
